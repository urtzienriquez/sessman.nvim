local env = require("tests.helpers.env")

describe(":Session / :S", function()
  local sessman, connects

  before_each(function()
    env.setup()
    vim.cmd("runtime plugin/sessman.lua")
    sessman = env.fresh("sessman")
    env.fresh("sessman.buffer")
    connects = env.stub_connect()
    env.write_session(env.project, "coding")
  end)

  after_each(env.teardown)

  local function last_error()
    return env.echoed[#env.echoed]
  end

  it("without arguments opens the list, also as :S", function()
    vim.cmd("S")
    assert.equals("sessman://sessions", vim.api.nvim_buf_get_name(0))
  end)

  it("is strict: the first word is a subcommand", function()
    vim.cmd("Session coding")
    assert.matches("unknown subcommand 'coding'", last_error())
    assert.equals(0, #connects)
  end)

  it("load starts a server for a session; connect needs one", function()
    vim.cmd("Session connect coding")
    assert.matches("coding has no server; to start one: :Session load coding", last_error())
    vim.cmd("Session load coding")
    assert.equals(sessman.session(env.project, "coding").sock, connects[1].addr)
    vim.cmd("Session connect nope")
    assert.matches("no session nope; to create it: :Session new nope", last_error())
    assert.equals(1, #connects)
  end)

  it("connect - goes to the previous server", function()
    vim.cmd("S connect -")
    assert.matches("no previous server", last_error())
    vim.cmd("S new one")
    vim.cmd("S connect -")
    assert.equals(2, #connects)
  end)

  it("new creates, but not over an existing session", function()
    vim.cmd("Session new coding")
    assert.matches("coding exists; to go there: :Session load coding", last_error())
    vim.cmd("Session new fresh")
    assert.equals(sessman.session(env.project, "fresh").sock, connects[1].addr)
    assert.equals(1, #connects)
  end)

  it("save names a plain nvim; save! overwrites", function()
    vim.cmd("Session save coding")
    assert.matches("add ! to override", last_error())
    vim.cmd("Session! save coding")
    assert.equals("coding", vim.g.sessman_session.name)
  end)

  it("stop and delete need an existing session", function()
    vim.cmd("Session stop nope")
    assert.matches("no session nope", last_error())
    vim.cmd("Session delete")
    assert.matches("argument required", last_error())
    env.stub_confirm(1)
    vim.cmd("Session delete coding")
    assert.equals(0, vim.fn.filereadable(sessman.session(env.project, "coding").file))
  end)

  it("new takes project:name; ':' always separates project and name", function()
    vim.fn.mkdir(env.root .. "/other", "p")
    vim.cmd("S new " .. env.root .. "/other:writing")
    assert.equals(sessman.session(env.root .. "/other", "writing").sock, connects[1].addr)
    sessman.save("a:b")
    assert.matches("unknown project: a", last_error())
  end)

  it("save ++shada gives the session its own ShaDa", function()
    vim.cmd("S save ++shada mine")
    local s = sessman.session(env.project, "mine")
    assert.equals(1, vim.fn.filereadable(s.shada))
    assert.equals(s.shada, vim.o.shadafile)
    vim.cmd("S connect ++shada coding")
    assert.matches("++shada only goes with save", last_error())
  end)

  it(":%S stop stops every other running session, asking once", function()
    vim.cmd("S new one")
    vim.cmd("S new two")
    local asked = env.stub_confirm(1)
    vim.cmd("%S stop")
    assert.same({ "Stop 2 servers?" }, asked)
    for _, s in ipairs(sessman.list()) do
      assert.is_true(not s.server or s.current, s.name .. " still running")
    end
  end)

  it("ignores a range with other subcommands (e.g. :'<,'> from visual mode)", function()
    vim.cmd("1,1S load coding")
    assert.equals(sessman.session(env.project, "coding").sock, connects[1].addr)
  end)

  it("rejects extra arguments", function()
    vim.cmd("Session connect a b")
    assert.matches("too many arguments", last_error())
  end)

  describe("completion", function()
    local function complete(line)
      return vim.fn.getcompletion(line, "cmdline")
    end

    it("completes subcommands first", function()
      assert.same({ "connect", "load", "new", "save", "stop", "delete" }, complete("Session "))
      assert.same({ "save" }, complete("S sa"))
    end)

    it("completes the sessions each subcommand can act on", function()
      vim.cmd("S new fresh") -- running, never saved; coding is saved only
      assert.same({ "-", "fresh" }, complete("Session connect "))
      assert.same({ "coding" }, complete("Session load "))
      assert.same({ "fresh" }, complete("vert Session stop "))
      assert.same({ "coding" }, complete("Session delete "))
      assert.same({ "++shada", "coding" }, complete("Session save "))
      assert.same({ "coding" }, complete("Session save ++shada "))
      assert.same({}, complete("Session connect coding "))
    end)

    it("completes directories for new", function()
      vim.fn.chdir(env.project)
      assert.same({ "sub/" }, complete("Session new s"))
    end)
  end)
end)
