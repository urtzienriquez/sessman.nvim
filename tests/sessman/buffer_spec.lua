local env = require("tests.helpers.env")

describe("sessman://sessions", function()
  local sessman, connects

  before_each(function()
    env.setup()
    vim.cmd("runtime plugin/sessman.lua")
    sessman = env.fresh("sessman")
    env.fresh("sessman.buffer")
    connects = env.stub_connect()
    env.write_session(env.project, "coding")
    env.write_session(false, "notes")
  end)

  after_each(env.teardown)

  local function lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
  end

  --- Lines of a section, without its title, or nil if it isn't shown.
  local function section(title)
    local l, out = lines(), nil
    for _, line in ipairs(l) do
      if out then
        if line == "" then
          break
        end
        out[#out + 1] = line
      elseif line:match("^" .. vim.pesc(title) .. " %(%d+%)$") then
        out = {}
      end
    end
    return out
  end

  --- Put the cursor on the entry of `name` in section `title`.
  local function goto_entry(title, name)
    local inside = false
    for i, line in ipairs(lines()) do
      if line:match("^" .. vim.pesc(title) .. " %(") then
        inside = true
      elseif inside and line == "" then
        break
      elseif inside and line:find("%f[%S]" .. vim.pesc(name) .. "%f[%s]") then
        return vim.api.nvim_win_set_cursor(0, { i, 0 })
      end
    end
    error(("no %s in %s"):format(name, title))
  end

  it("opens at the top spanning the full width, like fugitive's :Git", function()
    vim.cmd("vsplit")
    vim.cmd("Session")
    assert.equals(3, #vim.api.nvim_list_wins())
    assert.equals(1, vim.fn.winnr())
    assert.equals(vim.o.columns, vim.fn.winwidth(0))
    vim.cmd("close")
    vim.o.splitbelow = true
    vim.cmd("Session")
    assert.equals(vim.fn.winnr("$"), vim.fn.winnr(), "botright with 'splitbelow'")
    assert.equals(vim.o.columns, vim.fn.winwidth(0))
    vim.o.splitbelow = false
  end)

  it("shows headers", function()
    vim.cmd("Session")
    assert.equals("sessman", vim.bo.filetype)
    assert.equals("nofile", vim.bo.buftype)
    assert.is_false(vim.bo.modifiable)
    local l = lines()
    assert.equals("Session: none", l[1])
    assert.equals("Project: " .. vim.fn.fnamemodify(env.project, ":~"), l[2])
    assert.equals("Help:    g?", l[3])
    assert.equals("", l[4])
    assert.equals(vim.fn.fnamemodify(env.project, ":~") .. "  current", l[5])
    assert.equals("", l[6])
  end)

  it("groups by state: saved sessions by project, current project first", function()
    vim.fn.mkdir(env.root .. "/aaa", "p")
    env.write_session(env.root .. "/aaa", "x")
    env.write_session(env.project, "review")
    vim.cmd("Session")
    assert.is_nil(section("Running"), "empty sections are omitted")
    assert.same({
      "  " .. vim.fn.fnamemodify(env.project, ":~"),
      "    coding  saved just now",
      "    review  saved just now",
      "  " .. vim.fn.fnamemodify(env.root .. "/aaa", ":~"),
      "    x       saved just now",
      "  global",
      "    notes   saved just now",
    }, section("Saved"))
  end)

  it("lists running sessions with details; this plain nvim is only on top", function()
    sessman.switch("coding")
    sessman.create("fresh")
    vim.cmd("Session")
    assert.same({
      "  " .. vim.fn.fnamemodify(env.project, ":~"),
      "    coding  saved just now",
      "    fresh   never saved",
    }, section("Running"))
    assert.same({ "  global", "    notes  saved just now" }, section("Saved"))
    assert.is_nil(section("Unnamed nvim"))
  end)

  it("lists other plain nvims at the bottom as Unnamed", function()
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
    vim.cmd("Session")
    vim.fn.jobstop(job)
    assert.same({ "  " .. vim.fn.fnamemodify(env.project .. "/sub", ":~") .. "  plain nvim" }, section("Unnamed nvim"))
  end)

  it("once saved, the current session moves to Running", function()
    sessman.save("mine")
    sessman.switch("coding")
    local s = sessman.resolve("coding", sessman.list())
    env.remote(s.sock, "vim.fn.chdir('sub')")
    vim.cmd("Session")
    assert.equals("Session: mine", lines()[1])
    assert.equals("Running (2)", lines()[5])
    assert.is_nil(section("Unnamed nvim"))
    assert.same({
      "  " .. vim.fn.fnamemodify(env.project, ":~"),
      "    coding  saved just now, in sub/",
      "    mine    current, saved just now",
    }, section("Running"))
  end)

  it("opens in a split with <mods> when the buffer isn't empty", function()
    vim.cmd.edit(env.project .. "/a.txt")
    vim.cmd("vertical Session")
    assert.equals(2, #vim.api.nvim_list_wins())
    assert.equals("sessman://sessions", vim.api.nvim_buf_get_name(0))
    vim.cmd("wincmd p")
    vim.cmd("Session")
    assert.equals(2, #vim.api.nvim_list_wins(), "focuses the existing window")
  end)

  it("<CR> goes to the session under the cursor", function()
    vim.cmd("Session")
    goto_entry("Saved", "coding")
    env.feed("<CR>")
    assert.equals(sessman.new(env.project, "coding").sock, connects[1].addr)
    goto_entry("Running", "coding")
  end)

  it("X kills and D deletes", function()
    sessman.switch("coding")
    vim.cmd("Session")
    env.stub_confirm(1)
    goto_entry("Running", "coding")
    env.feed("X")
    goto_entry("Saved", "coding")
    env.feed("D")
    assert.same({ "  global", "    notes  saved just now" }, section("Saved"))
  end)

  it("s saves a running session", function()
    sessman.create("fresh")
    vim.cmd("Session")
    goto_entry("Running", "fresh")
    env.feed("s")
    local s = sessman.new(env.project, "fresh")
    assert.is_true(vim.wait(2000, function()
      return vim.fn.filereadable(s.file) == 1
    end, 10))
  end)

  it("navigates with ) ( ]] [[ and closes with gq", function()
    sessman.create("fresh")
    vim.cmd.edit(env.project .. "/a.txt")
    vim.cmd("Session")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    env.feed(")")
    assert.matches("current", vim.api.nvim_get_current_line())
    env.feed(")")
    assert.matches("fresh", vim.api.nvim_get_current_line())
    env.feed(")")
    assert.matches("coding", vim.api.nvim_get_current_line())
    env.feed("(")
    assert.matches("fresh", vim.api.nvim_get_current_line())
    env.feed("]]")
    assert.equals("Saved (2)", vim.api.nvim_get_current_line())
    env.feed("[[")
    assert.equals("Running (1)", vim.api.nvim_get_current_line())
    env.feed("gq")
    assert.equals(1, #vim.api.nvim_list_wins())
    assert.is_nil(env.find_buf("sessman://sessions"))
  end)

  it("replaces an empty stand-in restored by an old session file", function()
    vim.cmd("enew | file sessman://sessions")
    vim.cmd.edit(env.project .. "/a.txt")
    vim.cmd("Session")
    assert.equals("sessman", vim.bo.filetype)
    goto_entry("Saved", "coding")
  end)

  it("co/cn/cs<Space> start :Session switch/new/save", function()
    vim.cmd("Session")
    assert.equals(":Session switch ", vim.fn.maparg("co<Space>", "n"))
    assert.equals(":Session new ", vim.fn.maparg("cn<Space>", "n"))
    assert.equals(":Session save ", vim.fn.maparg("cs<Space>", "n"))
    assert.equals("", vim.fn.maparg("c<Space>", "n"))
  end)

  it(":edit re-reads it", function()
    vim.cmd("Session")
    env.write_session(env.project, "later")
    vim.cmd("edit")
    goto_entry("Saved", "later")
  end)
end)
