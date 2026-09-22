local env = require("tests.helpers.env")

local function ui_buf()
  return env.find_buf("sessman://session")
end

local function lines()
  return vim.api.nvim_buf_get_lines(ui_buf(), 0, -1, false)
end

describe("ui (save form)", function()
  local ui

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    env.fresh("sessman.session")
    ui = env.fresh("sessman.ui")
  end)

  after_each(function()
    env.teardown()
  end)

  it("opens an acwrite buffer in a new split with the default fields", function()
    local wins = #vim.api.nvim_list_wins()
    ui.open()
    local buf = ui_buf()
    assert.equals(wins + 1, #vim.api.nvim_list_wins())
    assert.equals(buf, vim.api.nvim_get_current_buf())
    assert.equals("acwrite", vim.bo[buf].buftype)
    assert.equals("sessman", vim.bo[buf].filetype)
    assert.is_false(vim.bo[buf].modifiable)
    assert.equals("Name:        Session.vim", lines()[1])
    assert.equals("Write shada? no", lines()[2])
    assert.equals("Project: " .. env.project .. "/", lines()[5])
    assert.same({ 1, 13 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("prefills the name from the current session", function()
    vim.v.this_session = "/somewhere/work.vim"
    ui.open()
    assert.equals("Name:        work.vim", lines()[1])
  end)

  it("focuses the existing window when opened twice", function()
    ui.open()
    local win = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")
    local count = #vim.api.nvim_list_wins()
    ui.open()
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.equals(count, #vim.api.nvim_list_wins())
  end)

  it("respects 'splitbelow' when choosing where to split", function()
    vim.o.splitbelow = true
    ui.open()
    vim.o.splitbelow = false
    assert.equals(vim.fn.winnr("$"), vim.fn.winnr())
  end)

  it("<CR> on the shada line toggles it", function()
    ui.open()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    env.feed("<CR>")
    assert.equals("Write shada? yes", lines()[2])
    env.feed("<CR>")
    assert.equals("Write shada? no", lines()[2])
    assert.same({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("<CR> on the name line renames the session", function()
    env.stub_input("mywork")
    ui.open()
    env.feed("<CR>")
    assert.equals("Name:        mywork.vim", lines()[1])
  end)

  it("ignores an empty or cancelled rename", function()
    ui.open()
    env.stub_input("")
    env.feed("<CR>")
    env.stub_input(nil)
    env.feed("<CR>")
    assert.equals("Name:        Session.vim", lines()[1])
  end)

  it(":w then closing the buffer saves the session with the chosen options", function()
    ui.open()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    env.feed("<CR>")
    vim.cmd("write")
    assert.is_false(vim.bo.modified)
    vim.cmd("close")
    local path = env.project_session_dir() .. "/Session.vim"
    vim.wait(1000, function()
      return vim.fn.filereadable(path) == 1
    end)
    assert.equals(1, vim.fn.filereadable(path))
    assert.equals(1, vim.fn.filereadable(env.project_session_dir() .. "/Session.shada"))
  end)

  it("closing without :w discards", function()
    ui.open()
    vim.cmd("close")
    vim.wait(100)
    assert.equals(0, vim.fn.isdirectory(env.project_session_dir()))
  end)

  it("]c / [c jump between fields", function()
    ui.open()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    env.feed("]c")
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1]) -- Project:
    env.feed("]c")
    assert.equals(7, vim.api.nvim_win_get_cursor(0)[1]) -- Help:
    env.feed("[c")
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("highlights labels and values", function()
    ui.open()
    local ns = vim.api.nvim_get_namespaces().sessman
    local groups = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(ui_buf(), ns, 0, -1, { details = true })) do
      groups[m[4].hl_group] = true
    end
    for _, g in ipairs({ "SessmanLabel", "SessmanValue", "SessmanBoolean", "SessmanSeparator", "SessmanPath" }) do
      assert.is_true(groups[g], g)
    end
  end)
end)
