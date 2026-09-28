-- Real headless servers are spawned; only :connect (which needs a UI) is stubbed.
local env = require("tests.helpers.env")

describe("servers", function()
  local sessman, connects

  before_each(function()
    env.setup()
    sessman = env.fresh("sessman")
    connects = env.stub_connect()
  end)

  after_each(env.teardown)

  local function get(target)
    return sessman.resolve(target, sessman.list())
  end

  it("creates a new session in the here project and connects to it", function()
    sessman.new("fresh")
    local s = get("fresh")
    assert.is_true(s.running)
    assert.is_nil(s.saved)
    assert.same({ { addr = s.sock, stop = true } }, connects)
    assert.same({ project = env.project, name = "fresh" }, env.remote(s.sock, "vim.g.sessman_session"))
    assert.equals(env.project, env.remote(s.sock, "vim.fn.getcwd()"))
  end)

  it("restores a saved session from its file, with its ShaDa", function()
    env.write_session(env.project, "coding", { "cd " .. vim.fn.fnameescape(env.project .. "/sub"), "let g:restored = 1" })
    vim.fn.writefile({}, sessman.session(env.project, "coding").shada)
    sessman.switch("coding")
    local s = get("coding")
    assert.is_true(s.running and s.saved)
    assert.equals(1, env.remote(s.sock, "vim.g.restored"))
    assert.equals(env.project .. "/sub", env.remote(s.sock, "vim.fn.getcwd()"))
    assert.equals(s.shada, env.remote(s.sock, "vim.o.shadafile"))
    assert.equals(env.project .. "/sub", s.cwd)
  end)

  it("restores window sizes at the launching UI's size", function()
    local columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 232, 56
    vim.cmd("vsplit | vert 1resize 104")
    local file = sessman.session(env.project, "sized").file
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.cmd("mksession! " .. vim.fn.fnameescape(file))
    vim.cmd("only")
    sessman.switch("sized")
    vim.o.columns, vim.o.lines = columns, lines
    local s = get("sized")
    assert.same({ 104, 127 }, env.remote(s.sock, "{ vim.fn.winwidth(1), vim.fn.winwidth(2) }"))
  end)

  it("jumps to a running session instead of spawning another", function()
    sessman.new("fresh")
    local pid = get("fresh").pid
    sessman.switch("fresh")
    assert.equals(2, #connects)
    assert.equals(pid, get("fresh").pid)
  end)

  it("stops the plain nvim it leaves when that loses nothing", function()
    vim.fn.writefile({ "x" }, env.project .. "/a.txt")
    vim.cmd.edit(env.project .. "/a.txt")
    sessman.new("fresh")
    assert.is_true(connects[1].stop)
  end)

  it("keeps a plain nvim with unsaved changes", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "work" })
    sessman.new("fresh")
    assert.is_false(connects[1].stop)
  end)

  it("keeps a plain nvim with a running terminal", function()
    vim.cmd("terminal sleep 30")
    sessman.new("fresh")
    assert.is_false(connects[1].stop)
  end)

  describe("switch() without a target: picker", function()
    local select = vim.ui.select
    after_each(function()
      vim.ui.select = select
    end)

    --- Record what the picker is offered: labels and prompt.
    local function capture()
      local seen = {}
      vim.ui.select = function(items, opts)
        seen.labels = vim.tbl_map(opts.format_item, items)
        seen.prompt = opts.prompt
      end
      return seen
    end

    it("{ running = true } offers only other running sessions", function()
      env.write_session(env.project, "coding")
      sessman.new("fresh")
      local seen = capture()
      sessman.switch({ running = true })
      assert.same({ vim.fn.fnamemodify(env.project, ":~") .. ":fresh  (running)" }, seen.labels)
      assert.equals("Running session ", seen.prompt)
    end)

    it("offers other plain nvims too, as (unnamed)", function()
      local job = vim.fn.jobstart({
        vim.v.progpath,
        "--clean",
        "--headless",
        "--cmd",
        [[call serverstart(printf('%s/nvim.%d.0', stdpath('run'), getpid()))]],
      }, { cwd = env.project .. "/sub" })
      vim.wait(2000, function()
        return #vim.fn.globpath(vim.fn.stdpath("run"), "nvim.*", false, true) > 0
      end)
      local seen = capture()
      sessman.switch({ running = true })
      vim.fn.jobstop(job)
      assert.same({ vim.fn.fnamemodify(env.project .. "/sub", ":~") .. ":(unnamed)  (running)" }, seen.labels)
    end)

    it("{ running = false } offers only sessions that aren't running", function()
      env.write_session(env.project, "coding")
      sessman.new("fresh")
      local seen = capture()
      sessman.switch({ running = false })
      assert.same({ vim.fn.fnamemodify(env.project, ":~") .. ":coding" }, seen.labels)
      assert.equals("Saved session ", seen.prompt)
    end)

    --- Pretend a running session was left `offset` seconds later than it was.
    local function left(name, offset)
      local path = sessman.session(env.project, name).sock .. ".json"
      local st = vim.json.decode(table.concat(vim.fn.readfile(path)))
      st.active = st.active + offset
      vim.fn.writefile({ vim.json.encode(st) }, path)
    end

    it("orders most recent first; the first running one is switch -'s", function()
      env.write_session(env.project, "coding")
      sessman.new("one")
      sessman.new("two")
      left("one", 100) -- left after two
      local p = vim.fn.fnamemodify(env.project, ":~")

      local seen = capture()
      sessman.switch({ running = true })
      assert.same({ p .. ":one  (running)", p .. ":two  (running)" }, seen.labels)
      assert.equals("one", sessman.previous().name)

      sessman.switch()
      assert.same({
        p .. ":one  (running)",
        p .. ":two  (running)",
        p .. ":coding",
        p .. ":(unnamed)  (current)",
      }, seen.labels)
    end)

    it("orders saved sessions by last save", function()
      local old = env.write_session(env.project, "old")
      env.write_session(env.project, "recent")
      vim.uv.fs_utime(old.file, os.time() - 3600, os.time() - 3600)
      local seen = capture()
      sessman.switch({ running = false })
      local p = vim.fn.fnamemodify(env.project, ":~")
      assert.same({ p .. ":recent", p .. ":old" }, seen.labels)
    end)

    it("says so when there is nothing to offer", function()
      local seen = capture()
      sessman.switch({ running = true })
      assert.is_nil(seen.labels)
      assert.matches("no other running session", env.echoed[#env.echoed])
    end)

    it("is what :S switch does (there is no separate pick())", function()
      env.write_session(env.project, "coding")
      vim.cmd("runtime plugin/sessman.lua")
      local seen = capture()
      vim.cmd("S switch")
      assert.equals(2, #seen.labels) -- coding + this plain nvim
      assert.is_nil(sessman.pick)
    end)

    it("labels sessions with their full project path", function()
      env.write_session(env.project, "coding")
      env.write_session(false, "notes")
      sessman.new("fresh")
      local labels
      vim.ui.select = function(items, opts)
        labels = vim.tbl_map(opts.format_item, items)
      end
      sessman.switch()
      table.sort(labels)
      local p = vim.fn.fnamemodify(env.project, ":~")
      local expected = { "global:notes", p .. ":coding", p .. ":fresh  (running)", p .. ":(unnamed)  (current)" }
      table.sort(expected)
      assert.same(expected, labels)
    end)

    --- A picker that, like fzf-lua, runs in a terminal still alive when it
    --- calls back.
    local function terminal_picker(choice)
      vim.ui.select = function(items, _, cb)
        vim.cmd("terminal sleep 30")
        for _, s in ipairs(items) do
          if s.name == choice then
            return cb(s)
          end
        end
      end
    end

    it("doesn't let the picker's terminal keep the plain nvim alive", function()
      env.write_session(env.project, "coding")
      terminal_picker("coding")
      sessman.switch()
      assert.is_true(vim.wait(5000, function()
        return #connects > 0
      end, 10))
      assert.is_true(connects[1].stop)
    end)

    it("still keeps it for a terminal that was open before", function()
      env.write_session(env.project, "coding")
      vim.cmd("terminal sleep 30")
      terminal_picker("coding")
      sessman.switch()
      assert.is_true(vim.wait(5000, function()
        return #connects > 0
      end, 10))
      assert.is_false(connects[1].stop)
    end)
  end)

  it("never stops a session it leaves", function()
    sessman.save("mine")
    sessman.new("fresh")
    assert.is_false(connects[1].stop)
  end)

  it("rejects invalid names", function()
    sessman.new("has space")
    assert.equals(0, #connects)
    assert.matches("invalid session name", env.echoed[#env.echoed])
  end)

  it(":Session - goes to the most recently left session", function()
    sessman.new("one")
    sessman.new("two")
    local one, two = get("one"), get("two")
    local path = one.sock .. ".json"
    local st = vim.json.decode(table.concat(vim.fn.readfile(path)))
    st.active = st.active + 100
    vim.fn.writefile({ vim.json.encode(st) }, path)
    assert.equals("one", sessman.previous().name)
    sessman.switch("-")
    assert.equals(one.sock, connects[#connects].addr)
    assert.is_true(two.running)
  end)

  it(":Session - without running sessions is an error", function()
    sessman.switch("-")
    assert.equals(0, #connects)
    assert.matches("no previous session", env.echoed[#env.echoed])
  end)

  it("kills another session after confirming, keeping its files", function()
    env.write_session(env.project, "coding")
    sessman.switch("coding")
    local s = get("coding")
    env.stub_confirm(2)
    sessman.kill(s)
    assert.is_true(get("coding").running)
    env.stub_confirm(1)
    sessman.kill(s)
    local after = get("coding")
    assert.is_nil(after.running)
    assert.is_true(after.saved)
  end)

  it("killing the current session from the list opens the list where it lands", function()
    sessman.new("one")
    sessman.new("two")
    local one, two = get("one"), get("two")
    -- Inside "two" (no UI there, so :connect is stubbed): kill itself
    env.remote(two.sock, "(function() require('sessman').connect = function() end end)()")
    pcall(env.remote, two.sock, [[(function()
      local m = require('sessman')
      for _, s in ipairs(m.list()) do
        if s.current then m.kill(s, true, true) end
      end
    end)()]])
    assert.is_true(vim.wait(2000, function()
      return not vim.uv.fs_stat(two.sock)
    end, 10), "two quit")
    assert.is_true(vim.wait(2000, function()
      return env.remote(one.sock, "vim.fn.bufexists('sessman://sessions')") == 1
    end, 10), "the list is open in one")
  end)

  it("deletes a running session: files removed and server stopped", function()
    env.write_session(env.project, "coding")
    sessman.switch("coding")
    local s = get("coding")
    env.stub_confirm(1)
    sessman.delete(s)
    assert.equals(0, vim.fn.filereadable(s.file))
    assert.equals(0, vim.fn.isdirectory(vim.fs.dirname(s.file)))
    assert.is_nil(get("coding").running)
  end)

  it("deleting a running session with its ShaDa leaves no .shada behind", function()
    sessman.new("fresh")
    local s = get("fresh")
    env.remote(s.sock, "require('sessman').save(nil, { shada = true })")
    assert.equals(1, vim.fn.filereadable(s.shada))
    env.stub_confirm(1)
    sessman.delete(get("fresh"))
    assert.is_nil(vim.uv.fs_stat(s.sock), "stopped")
    vim.wait(300) -- it would rewrite its ShaDa while exiting
    assert.equals(0, vim.fn.filereadable(s.shada))
    assert.equals(0, vim.fn.filereadable(s.file))
  end)

  it("saves another running session remotely", function()
    sessman.new("fresh")
    local s = get("fresh")
    sessman.save_remote(s)
    assert.is_true(vim.wait(2000, function()
      return vim.fn.filereadable(s.file) == 1
    end, 10))
  end)

  it("keeps the status file current", function()
    sessman.new("fresh")
    local s = get("fresh")
    env.remote(s.sock, "vim.fn.chdir('sub')")
    assert.equals(env.project .. "/sub", get("fresh").cwd)
  end)
end)
