local env = require("tests.helpers.env")

local function list_buf()
  return env.find_buf("sessman://sessions")
end

local function lines()
  return vim.api.nvim_buf_get_lines(list_buf(), 0, -1, false)
end

local function line_of(text)
  for i, l in ipairs(lines()) do
    if l == text then
      return i
    end
  end
end

describe("list (session list buffer)", function()
  local list, now

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    env.fresh("sessman.session")
    env.fresh("sessman.backends")
    env.fresh("sessman.picker")
    list = env.fresh("sessman.list")
    now = os.time()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_augroup_by_name, "SessmanList")
    env.teardown()
  end)

  it("shows only the header when the project has no sessions", function()
    list.open()
    local buf = list_buf()
    assert.equals("nofile", vim.bo[buf].buftype)
    assert.equals("sessman-list", vim.bo[buf].filetype)
    assert.is_false(vim.bo[buf].modifiable)
    assert.same({ "Project:  " .. env.project .. "/", "Help:     g?" }, lines())
  end)

  it("lists sessions newest first under a counted heading", function()
    env.write_session("old.vim", nil, now - 100)
    env.write_session("new.vim", nil, now)
    list.open()
    local l = lines()
    assert.equals("Sessions (2)", l[4])
    assert.equals("○  new.vim", l[5])
    assert.equals("○  old.vim", l[6])
  end)

  it("marks the loaded session with the active icon", function()
    env.write_session("a.vim", nil, now)
    vim.v.this_session = env.write_session("b.vim", nil, now - 10)
    list.open()
    assert.is_not_nil(line_of("●  b.vim"))
    assert.is_not_nil(line_of("○  a.vim"))
  end)

  it("focuses and refreshes the existing window when opened twice", function()
    list.open()
    local win = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")
    env.write_session("x.vim")
    list.open()
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.is_not_nil(line_of("○  x.vim"))
  end)

  it("R refreshes after sessions change on disk", function()
    list.open()
    env.write_session("x.vim")
    env.feed("R")
    assert.is_not_nil(line_of("○  x.vim"))
  end)

  it("re-renders when the project changes", function()
    list.open()
    local other = env.root .. "/other"
    vim.fn.mkdir(other, "p")
    require("sessman.project").set(other)
    assert.equals("Project:  " .. other .. "/", lines()[1])
  end)

  it("]c / [c move between entries and wrap around", function()
    env.write_session("a.vim", nil, now)
    env.write_session("b.vim", nil, now - 10)
    list.open()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    env.feed("]c")
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])
    env.feed("]c")
    assert.equals(6, vim.api.nvim_win_get_cursor(0)[1])
    env.feed("]c")
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])
    env.feed("[c")
    assert.equals(6, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("gs jumps to the Sessions heading", function()
    env.write_session("a.vim")
    list.open()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    env.feed("gs")
    assert.equals(4, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("dd deletes the session under the cursor and re-renders", function()
    env.write_session("a.vim", nil, now)
    env.write_session("b.vim", nil, now - 10)
    env.stub_select("Yes")
    list.open()
    vim.api.nvim_win_set_cursor(0, { line_of("○  a.vim"), 0 })
    env.feed("dd")
    assert.equals(0, vim.fn.filereadable(env.project_session_dir() .. "/a.vim"))
    assert.equals("Sessions (1)", lines()[4])
  end)

  it("dd on a non-session line warns", function()
    local notes = env.capture_notify()
    list.open()
    env.feed("dd")
    assert.is_true(env.notified(notes, "No session on this line", vim.log.levels.WARN))
  end)

  it("<CR> loads the session under the cursor", function()
    env.write_session("a.vim", { "let g:sessman_list_loaded = 'a'" })
    list.open()
    vim.api.nvim_win_set_cursor(0, { line_of("○  a.vim"), 0 })
    env.feed("<CR>")
    assert.equals("a", vim.g.sessman_list_loaded)
  end)

  it("<CR> falls back to the project-local Session.vim", function()
    vim.fn.writefile({ "let g:sessman_list_local = 1" }, env.project .. "/Session.vim")
    list.open()
    env.feed("<CR>")
    assert.equals(1, vim.g.sessman_list_local)
  end)

  it("<CR> warns when there is nothing to load", function()
    local notes = env.capture_notify()
    list.open()
    env.feed("<CR>")
    assert.is_true(env.notified(notes, "No session on this line", vim.log.levels.WARN))
  end)

  it("cx clears the project", function()
    list.open()
    env.feed("cx")
    assert.is_nil(vim.g.sessman_project)
  end)

  it("ss opens the save form", function()
    list.open()
    env.feed("ss")
    assert.is_not_nil(env.find_buf("sessman://session"))
  end)

  it("ii toggles the info view", function()
    list.open()
    env.feed("ii")
    assert.is_not_nil(env.find_buf("sessman://info"))
  end)

  it("pp sets the project from the picker backend", function()
    local other = env.root .. "/other"
    vim.fn.mkdir(other, "p")
    require("sessman.backends").register("fzf", {
      pick_directory = function(cb)
        cb(other)
      end,
    })
    require("sessman.config").set({ session_dir = env.session_dir, backend = "fzf" })
    list.open()
    env.feed("pp")
    assert.equals(other .. "/", vim.g.sessman_project)
  end)

  it("mq closes the window", function()
    list.open()
    env.feed("mq")
    assert.is_nil(list_buf())
  end)
end)
