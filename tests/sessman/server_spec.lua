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
    sessman.go("fresh")
    local s = get("fresh")
    assert.is_true(s.running)
    assert.is_nil(s.saved)
    assert.same({ { addr = s.sock, stop = true } }, connects)
    assert.same({ project = env.project, name = "fresh" }, env.remote(s.sock, "vim.g.sessman_session"))
    assert.equals(env.project, env.remote(s.sock, "vim.fn.getcwd()"))
  end)

  it("restores a saved session from its file, with its ShaDa", function()
    env.write_session(env.project, "coding", { "cd " .. vim.fn.fnameescape(env.project .. "/sub"), "let g:restored = 1" })
    vim.fn.writefile({}, sessman.new(env.project, "coding").shada)
    sessman.go("coding")
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
    local file = sessman.new(env.project, "sized").file
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    vim.cmd("mksession! " .. vim.fn.fnameescape(file))
    vim.cmd("only")
    sessman.go("sized")
    vim.o.columns, vim.o.lines = columns, lines
    local s = get("sized")
    assert.same({ 104, 127 }, env.remote(s.sock, "{ vim.fn.winwidth(1), vim.fn.winwidth(2) }"))
  end)

  it("jumps to a running session instead of spawning another", function()
    sessman.go("fresh")
    local pid = get("fresh").pid
    sessman.go("fresh")
    assert.equals(2, #connects)
    assert.equals(pid, get("fresh").pid)
  end)

  it("stops the plain nvim it leaves when that loses nothing", function()
    vim.fn.writefile({ "x" }, env.project .. "/a.txt")
    vim.cmd.edit(env.project .. "/a.txt")
    sessman.go("fresh")
    assert.is_true(connects[1].stop)
  end)

  it("keeps a plain nvim with unsaved changes", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "work" })
    sessman.go("fresh")
    assert.is_false(connects[1].stop)
  end)

  it("keeps a plain nvim with a running terminal", function()
    vim.cmd("terminal sleep 30")
    sessman.go("fresh")
    assert.is_false(connects[1].stop)
  end)

  describe("pick()", function()
    local select = vim.ui.select
    after_each(function()
      vim.ui.select = select
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
      sessman.pick()
      assert.is_true(vim.wait(5000, function()
        return #connects > 0
      end, 10))
      assert.is_true(connects[1].stop)
    end)

    it("still keeps it for a terminal that was open before", function()
      env.write_session(env.project, "coding")
      vim.cmd("terminal sleep 30")
      terminal_picker("coding")
      sessman.pick()
      assert.is_true(vim.wait(5000, function()
        return #connects > 0
      end, 10))
      assert.is_false(connects[1].stop)
    end)
  end)

  it("never stops a session it leaves", function()
    sessman.save("mine")
    sessman.go("fresh")
    assert.is_false(connects[1].stop)
  end)

  it("rejects invalid names", function()
    sessman.go("has space")
    assert.equals(0, #connects)
    assert.matches("invalid session name", env.echoed[#env.echoed])
  end)

  it(":Session - goes to the most recently left session", function()
    sessman.go("one")
    sessman.go("two")
    local one, two = get("one"), get("two")
    local path = one.sock .. ".json"
    local st = vim.json.decode(table.concat(vim.fn.readfile(path)))
    st.active = st.active + 100
    vim.fn.writefile({ vim.json.encode(st) }, path)
    assert.equals("one", sessman.previous().name)
    sessman.go("-")
    assert.equals(one.sock, connects[#connects].addr)
    assert.is_true(two.running)
  end)

  it(":Session - without running sessions is an error", function()
    sessman.go("-")
    assert.equals(0, #connects)
    assert.matches("no previous session", env.echoed[#env.echoed])
  end)

  it("kills another session after confirming, keeping its files", function()
    env.write_session(env.project, "coding")
    sessman.go("coding")
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

  it("deletes a running session: files removed and server stopped", function()
    env.write_session(env.project, "coding")
    sessman.go("coding")
    local s = get("coding")
    env.stub_confirm(1)
    sessman.delete(s)
    assert.equals(0, vim.fn.filereadable(s.file))
    assert.equals(0, vim.fn.isdirectory(vim.fs.dirname(s.file)))
    assert.is_nil(get("coding").running)
  end)

  it("saves another running session remotely", function()
    sessman.go("fresh")
    local s = get("fresh")
    sessman.save_remote(s)
    assert.is_true(vim.wait(2000, function()
      return vim.fn.filereadable(s.file) == 1
    end, 10))
  end)

  it("keeps the status file current", function()
    sessman.go("fresh")
    local s = get("fresh")
    env.remote(s.sock, "vim.fn.chdir('sub')")
    assert.equals(env.project .. "/sub", get("fresh").cwd)
  end)
end)
