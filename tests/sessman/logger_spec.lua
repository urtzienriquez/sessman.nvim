local env = require("tests.helpers.env")

describe("logger", function()
  local logger, log_file, orig_state

  before_each(function()
    env.setup()
    orig_state = vim.env.XDG_STATE_HOME
    vim.env.XDG_STATE_HOME = env.root .. "/state"
    vim.fn.mkdir(vim.fn.stdpath("state"), "p")
    log_file = vim.fn.stdpath("state") .. "/sessman-debug.log"
    logger = env.fresh("sessman.logger")
  end)

  after_each(function()
    vim.g.sessman_debug = nil
    vim.env.SESSMAN_DEBUG = nil
    pcall(vim.api.nvim_del_augroup_by_name, "SessmanDebugLogger")
    vim.env.XDG_STATE_HOME = orig_state
    env.teardown()
  end)

  local function contents()
    return table.concat(vim.fn.readfile(log_file), "\n")
  end

  it("writes to stdpath('state')/sessman-debug.log", function()
    assert.equals(env.root .. "/state/nvim/sessman-debug.log", log_file)
  end)

  it("does nothing when debugging is off", function()
    logger.log("TestEvent")
    assert.equals(0, vim.fn.filereadable(log_file))
  end)

  it("logs the event, buffer info and a traceback when g:sessman_debug is set", function()
    vim.g.sessman_debug = true
    logger.log("TestEvent")
    local text = contents()
    assert.truthy(text:find("TestEvent", 1, true))
    assert.truthy(text:find("valid = true", 1, true))
    assert.truthy(text:find("stack", 1, true))
  end)

  it("logs when $SESSMAN_DEBUG=1", function()
    vim.env.SESSMAN_DEBUG = "1"
    logger.log("EnvEvent")
    assert.truthy(contents():find("EnvEvent", 1, true))
  end)

  it("handles an invalid buffer", function()
    vim.g.sessman_debug = true
    logger.log("Gone", 99999)
    assert.truthy(contents():find("valid = false", 1, true))
  end)

  it("setup() logs terminal buffers but not regular ones", function()
    vim.g.sessman_debug = true
    logger.setup()
    vim.cmd.edit(env.root .. "/plain.txt")
    assert.equals(0, vim.fn.filereadable(log_file))
    vim.cmd("terminal true")
    assert.truthy(contents():find("TermOpen", 1, true))
  end)
end)
