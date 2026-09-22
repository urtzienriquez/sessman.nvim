local env = require("tests.helpers.env")

local plugin_mods = {
  "fzf-lua",
  "fzf-lua.actions",
  "fzf-lua.path",
  "telescope",
  "telescope.pickers",
  "telescope.finders",
  "telescope.config",
  "telescope.actions",
  "telescope.actions.state",
  "mini.pick",
  "snacks",
}
local backend_mods = {
  "sessman.backends.fzf",
  "sessman.backends.telescope",
  "sessman.backends.minipick",
  "sessman.backends.snacks",
}

local function reset_modules()
  for _, m in ipairs(plugin_mods) do
    package.loaded[m] = nil
  end
  for _, m in ipairs(backend_mods) do
    package.loaded[m] = nil
  end
end

describe("backends registry", function()
  local backends

  before_each(function()
    env.setup()
    reset_modules()
    backends = env.fresh("sessman.backends")
  end)

  after_each(function()
    reset_modules()
    env.teardown()
  end)

  it("get() returns nil when no backend is available", function()
    assert.is_nil(backends.get())
  end)

  it("get() returns a registered backend for the configured name", function()
    local fake = {}
    backends.register("snacks", fake)
    require("sessman.config").set({ session_dir = env.session_dir, backend = "snacks" })
    assert.equals(fake, backends.get())
  end)

  it("get() lazy-loads sessman.backends.<name>", function()
    package.loaded["sessman.backends.minipick"] = { lazily = true }
    require("sessman.config").set({ session_dir = env.session_dir, backend = "minipick" })
    assert.is_true(backends.get().lazily)
  end)

  it("get() reports a backend module that fails to load", function()
    local notes = env.capture_notify()
    -- fzf backend requires fzf-lua at load time, which is not installed
    require("sessman.config").set({ session_dir = env.session_dir, backend = "fzf" })
    assert.is_nil(backends.get())
    assert.is_true(env.notified(notes, "backend 'fzf' could not be loaded", vim.log.levels.ERROR))
  end)

  it("call() warns when there is no backend", function()
    local notes = env.capture_notify()
    backends.call("pick_session")
    assert.is_true(env.notified(notes, "no picker backend found", vim.log.levels.WARN))
  end)

  it("call() warns when the backend lacks the function", function()
    local notes = env.capture_notify()
    backends.register("snacks", {})
    require("sessman.config").set({ session_dir = env.session_dir, backend = "snacks" })
    backends.call("pick_session")
    assert.is_true(env.notified(notes, "does not support 'pick_session'", vim.log.levels.WARN))
  end)

  it("call() forwards all arguments", function()
    local got
    backends.register("snacks", {
      pick_session = function(...)
        got = { ... }
      end,
    })
    require("sessman.config").set({ session_dir = env.session_dir, backend = "snacks" })
    backends.call("pick_session", { "a.vim" }, "/dir", print)
    assert.same({ { "a.vim" }, "/dir", print }, got)
  end)

  for _, name in ipairs({ "telescope", "minipick", "snacks" }) do
    it(name .. " backend degrades to an empty module when its plugin is missing", function()
      assert.same({}, require("sessman.backends." .. name))
    end)
  end
end)

--- Waits for vim.schedule'd callbacks to run.
local function flush()
  vim.wait(50, function()
    return false
  end)
end

describe("backend implementations", function()
  local session_dir, picked

  before_each(function()
    env.setup()
    reset_modules()
    env.fake_bin("fdfind", "echo " .. vim.fn.expand("~") .. "/code\necho rel/dir")
    env.write_session("a.vim")
    env.write_session("b.vim")
    session_dir = env.project_session_dir()
    picked = nil
  end)

  after_each(function()
    reset_modules()
    env.teardown()
  end)

  local function cb(v)
    picked = v
  end

  describe("fzf", function()
    local calls

    before_each(function()
      calls = {}
      package.loaded["fzf-lua"] = {
        files = function(opts)
          calls[#calls + 1] = { "files", opts }
        end,
        fzf_exec = function(items, opts)
          calls[#calls + 1] = { "fzf_exec", opts, items }
        end,
      }
      package.loaded["fzf-lua.actions"] = { toggle_hidden = function() end }
      package.loaded["fzf-lua.path"] = {
        entry_to_file = function(sel)
          return { path = sel }
        end,
      }
    end)

    it("pick_directory runs fzf.files from $HOME and returns an absolute path", function()
      local fzf = require("sessman.backends.fzf")
      fzf.pick_directory(cb)
      local opts = calls[1][2]
      assert.equals("files", calls[1][1])
      assert.equals(vim.fn.expand("~"), opts.cwd)
      assert.truthy(opts.fd_opts:find("--type d", 1, true))
      opts.actions.default({ "projects/foo" }, { cwd = env.root })
      assert.equals(env.root .. "/projects/foo", picked)
    end)

    it("pick_directory ignores an empty selection", function()
      local fzf = require("sessman.backends.fzf")
      fzf.pick_directory(cb)
      calls[1][2].actions.default({}, { cwd = env.root })
      assert.is_nil(picked)
    end)

    it("pick_session lists the files and returns the chosen one", function()
      local fzf = require("sessman.backends.fzf")
      fzf.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      assert.same({ "a.vim", "b.vim" }, calls[1][3])
      calls[1][2].actions.default({ "b.vim" })
      flush()
      assert.equals("b.vim", picked)
    end)

    it("ctrl-x deletes the session and reopens the picker with the rest", function()
      env.stub_select("Yes")
      local fzf = require("sessman.backends.fzf")
      fzf.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      calls[1][2].actions["ctrl-x"].fn({ "a.vim" })
      assert.equals(0, vim.fn.filereadable(session_dir .. "/a.vim"))
      assert.equals(2, #calls)
      assert.same({ "b.vim" }, calls[2][3])
    end)
  end)

  describe("telescope", function()
    local spec, maps, closed, selected

    before_each(function()
      spec, maps, closed, selected = nil, { i = {}, n = {} }, 0, nil
      package.loaded["telescope"] = {}
      package.loaded["telescope.pickers"] = {
        new = function(_, s)
          spec = s
          return {
            find = function()
              s.attach_mappings(1, function(mode, lhs, fn)
                maps[mode][lhs] = fn
              end)
            end,
          }
        end,
      }
      package.loaded["telescope.finders"] = {
        new_table = function(t)
          return t
        end,
      }
      package.loaded["telescope.config"] = { values = { generic_sorter = function() end } }
      package.loaded["telescope.actions"] = {
        close = function()
          closed = closed + 1
        end,
      }
      package.loaded["telescope.actions.state"] = {
        get_selected_entry = function()
          return selected
        end,
      }
    end)

    it("pick_directory lists fdfind results and resolves relative paths against $HOME", function()
      local ts = require("sessman.backends.telescope")
      ts.pick_directory(cb)
      assert.same({ vim.fn.expand("~") .. "/code", "rel/dir" }, spec.finder.results)
      selected = { "rel/dir" }
      maps.i["<CR>"]()
      assert.equals(1, closed)
      assert.equals(vim.fn.expand("~") .. "/rel/dir", (picked:gsub("/$", "")))
    end)

    it("pick_session returns the selected entry", function()
      local ts = require("sessman.backends.telescope")
      ts.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      assert.equals("Sessions", spec.prompt_title)
      selected = { "a.vim" }
      maps.n["<CR>"]()
      flush()
      assert.equals("a.vim", picked)
    end)

    it("<C-x> deletes the session and reopens the picker", function()
      env.stub_select("Yes")
      local ts = require("sessman.backends.telescope")
      ts.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      selected = { "a.vim" }
      maps.i["<C-x>"]()
      flush()
      assert.equals(0, vim.fn.filereadable(session_dir .. "/a.vim"))
      assert.same({ "b.vim" }, spec.finder.results)
    end)
  end)

  describe("minipick", function()
    local starts, stopped, current

    before_each(function()
      starts, stopped, current = {}, 0, nil
      package.loaded["mini.pick"] = {
        start = function(opts)
          starts[#starts + 1] = opts
        end,
        stop = function()
          stopped = stopped + 1
        end,
        get_picker_matches = function()
          return { current = current }
        end,
      }
    end)

    it("pick_directory lists fdfind results and returns an absolute path", function()
      local mp = require("sessman.backends.minipick")
      mp.pick_directory(cb)
      assert.same({ vim.fn.expand("~") .. "/code", "rel/dir" }, starts[1].source.items)
      starts[1].source.choose(env.root)
      assert.equals(env.root .. "/", picked)
    end)

    it("pick_session returns the chosen item", function()
      local mp = require("sessman.backends.minipick")
      mp.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      starts[1].source.choose("b.vim")
      flush()
      assert.equals("b.vim", picked)
    end)

    it("<C-x> stops the picker, deletes and restarts with the remaining sessions", function()
      env.stub_select("Yes")
      local mp = require("sessman.backends.minipick")
      mp.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      current = "a.vim"
      starts[1].mappings.delete_session.func()
      flush()
      assert.equals(1, stopped)
      assert.equals(0, vim.fn.filereadable(session_dir .. "/a.vim"))
      assert.same({ "b.vim" }, starts[2].source.items)
    end)
  end)

  describe("snacks", function()
    local pickers, fake_picker, sel

    before_each(function()
      pickers, sel = {}, nil
      fake_picker = {
        closed = 0,
        close = function(self)
          self.closed = self.closed + 1
        end,
        selected = function()
          return { sel }
        end,
      }
      package.loaded["snacks"] = {
        picker = function(opts)
          pickers[#pickers + 1] = opts
        end,
      }
    end)

    it("pick_directory searches directories under $HOME", function()
      local sn = require("sessman.backends.snacks")
      sn.pick_directory(cb)
      assert.same({ vim.fn.expand("~") }, pickers[1].dirs)
      pickers[1].confirm(fake_picker, { file = env.root })
      assert.equals(1, fake_picker.closed)
      assert.equals(env.root .. "/", picked)
    end)

    it("pick_session maps files to items and returns the chosen value", function()
      local sn = require("sessman.backends.snacks")
      sn.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      assert.equals("a.vim", pickers[1].items[1].value)
      pickers[1].confirm(fake_picker, pickers[1].items[2])
      flush()
      assert.equals("b.vim", picked)
    end)

    it("delete_session removes the session and reopens the picker", function()
      env.stub_select("Yes")
      local sn = require("sessman.backends.snacks")
      sn.pick_session({ "a.vim", "b.vim" }, session_dir, cb)
      sel = pickers[1].items[1]
      pickers[1].actions.delete_session(fake_picker)
      flush()
      assert.equals(0, vim.fn.filereadable(session_dir .. "/a.vim"))
      assert.equals("b.vim", pickers[2].items[1].value)
    end)
  end)
end)
