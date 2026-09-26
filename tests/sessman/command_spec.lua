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

  it("switch goes to saved sessions, but doesn't create", function()
    vim.cmd("Session switch coding")
    assert.equals(sessman.new(env.project, "coding").sock, connects[1].addr)
    vim.cmd("Session switch nope")
    assert.matches("no session nope; to create it: :Session new nope", last_error())
    assert.equals(1, #connects)
  end)

  it("switch - goes to the previous session", function()
    vim.cmd("S switch -")
    assert.matches("no previous session", last_error())
    vim.cmd("S new one")
    vim.cmd("S switch -")
    assert.equals(2, #connects)
  end)

  it("new creates, but not over an existing session", function()
    vim.cmd("Session new coding")
    assert.matches("coding exists; to go there: :Session switch coding", last_error())
    vim.cmd("Session new fresh")
    assert.equals(sessman.new(env.project, "fresh").sock, connects[1].addr)
    assert.equals(1, #connects)
  end)

  it("save names a plain nvim; save! overwrites", function()
    vim.cmd("Session save coding")
    assert.matches("add ! to override", last_error())
    vim.cmd("Session! save coding")
    assert.equals("coding", vim.g.sessman_session.name)
  end)

  it("kill and delete need an existing session", function()
    vim.cmd("Session kill nope")
    assert.matches("no session nope", last_error())
    vim.cmd("Session delete")
    assert.matches("argument required", last_error())
    env.stub_confirm(1)
    vim.cmd("Session delete coding")
    assert.equals(0, vim.fn.filereadable(sessman.new(env.project, "coding").file))
  end)

  it("new takes project:name; ':' always separates project and name", function()
    vim.fn.mkdir(env.root .. "/other", "p")
    vim.cmd("S new " .. env.root .. "/other:writing")
    assert.equals(sessman.new(env.root .. "/other", "writing").sock, connects[1].addr)
    sessman.save("a:b")
    assert.matches("unknown project: a", last_error())
  end)

  it("rejects extra arguments", function()
    vim.cmd("Session switch a b")
    assert.matches("too many arguments", last_error())
  end)

  describe("completion", function()
    local function complete(line)
      return vim.fn.getcompletion(line, "cmdline")
    end

    it("completes subcommands first", function()
      assert.same({ "switch", "new", "save", "kill", "delete" }, complete("Session "))
      assert.same({ "save" }, complete("S sa"))
    end)

    it("completes sessions (and - for switch)", function()
      assert.same({ "-", "coding" }, complete("Session switch "))
      assert.same({ "coding" }, complete("vert Session kill "))
      assert.same({}, complete("Session switch coding "))
    end)

    it("completes directories for new", function()
      vim.fn.chdir(env.project)
      assert.same({ "sub/" }, complete("Session new s"))
    end)
  end)
end)
