local env = require("tests.helpers.env")

local COMMANDS = {
  "SessionSave",
  "SessionSaveCurrent",
  "SessionLoad",
  "SessionDelete",
  "SessionProjectSet",
  "SessionProjectPick",
  "SessionProjectClear",
  "SessionCurrent",
  "SessionInfo",
  "SessionTmuxSync",
  "SessionDebugStart",
  "SessionDebugStop",
}

describe("sessman (init)", function()
  local sessman

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    sessman = env.fresh("sessman")
  end)

  after_each(function()
    vim.g.sessman_debug = nil
    env.teardown()
  end)

  describe("init()", function()
    it("registers all user commands", function()
      sessman.init()
      local cmds = vim.api.nvim_get_commands({})
      for _, name in ipairs(COMMANDS) do
        assert.is_not_nil(cmds[name], name)
      end
    end)

    it("sets g:sessman_project to the cwd with project_detection = auto", function()
      vim.g.sessman_project = nil
      vim.fn.chdir(env.root)
      sessman.init()
      assert.equals(env.root, vim.g.sessman_project)
    end)

    it("keeps an existing g:sessman_project", function()
      sessman.init()
      assert.equals(env.project, vim.g.sessman_project)
    end)

    it("leaves g:sessman_project unset with project_detection = manual", function()
      vim.g.sessman_project = nil
      env.fresh("sessman.config").set({ session_dir = env.session_dir, project_detection = "manual" })
      sessman.init()
      assert.is_nil(vim.g.sessman_project)
    end)

    it("is idempotent", function()
      sessman.init()
      vim.g.sessman_project = nil
      sessman.init()
      assert.is_nil(vim.g.sessman_project)
    end)

    it("defines the highlight groups and reapplies them on ColorScheme", function()
      sessman.init()
      assert.equals("PreProc", vim.api.nvim_get_hl(0, { name = "SessmanHeading", link = true }).link)
      vim.cmd("highlight clear SessmanHeading")
      vim.api.nvim_exec_autocmds("ColorScheme", {})
      assert.equals("PreProc", vim.api.nvim_get_hl(0, { name = "SessmanHeading", link = true }).link)
    end)

    it("creates the SessmanSession autocmds", function()
      sessman.init()
      local pre = vim.api.nvim_get_autocmds({ group = "SessmanSession", event = "SessionLoadPre" })
      local post = vim.api.nvim_get_autocmds({ group = "SessmanSession", event = "SessionLoadPost" })
      assert.equals(1, #pre)
      assert.equals(1, #post)
    end)

    it("sets up the debug logger when g:sessman_debug is set", function()
      vim.g.sessman_debug = true
      sessman.init()
      assert.is_true(#vim.api.nvim_get_autocmds({ group = "SessmanDebugLogger" }) > 0)
    end)
  end)

  describe("setup()", function()
    it("applies options and initializes", function()
      sessman.setup({ session_dir = env.session_dir, info = { active_icon = "!" } })
      assert.equals("!", require("sessman.config").get().info.active_icon)
      assert.is_not_nil(vim.api.nvim_get_commands({}).SessionSave)
    end)
  end)

  describe("SessionLoad autocmds", function()
    local dir, session_file, shada_file

    before_each(function()
      sessman.init()
      session_file = env.write_session("work.vim")
      dir = env.project_session_dir()
      shada_file = dir .. "/work.shada"
      vim.v.this_session = session_file
    end)

    it("SessionLoadPost switches to the session's shada when it exists", function()
      vim.cmd("wshada! " .. vim.fn.fnameescape(shada_file))
      vim.api.nvim_exec_autocmds("SessionLoadPost", {})
      assert.equals(shada_file, vim.o.shadafile)
      local win = require("sessman.info").open()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
      assert.truthy(text:find("Loaded Session", 1, true))
      assert.truthy(text:find("Loaded ShaDa", 1, true))
    end)

    it("SessionLoadPost falls back to the global shada when there is none", function()
      vim.api.nvim_exec_autocmds("SessionLoadPost", {})
      assert.equals("", vim.o.shadafile)
    end)

    it("SessionLoadPost does nothing without v:this_session", function()
      vim.v.this_session = ""
      vim.api.nvim_exec_autocmds("SessionLoadPost", {})
      assert.equals("NONE", vim.o.shadafile)
    end)

    it("SessionLoadPost only handles the first fire of a load", function()
      vim.api.nvim_exec_autocmds("SessionLoadPost", {})
      vim.o.shadafile = "NONE"
      vim.api.nvim_exec_autocmds("SessionLoadPost", {})
      assert.equals("NONE", vim.o.shadafile)
    end)

    it("SessionLoadPre writes the shada when it is the one in use", function()
      vim.cmd("wshada! " .. vim.fn.fnameescape(shada_file))
      local old = os.time() - 1000
      vim.uv.fs_utime(shada_file, old, old)
      vim.o.shadafile = shada_file
      vim.api.nvim_exec_autocmds("SessionLoadPre", {})
      assert.is_true(vim.fn.getftime(shada_file) > old)
    end)

    it("SessionLoadPre leaves the shada alone when another one is in use", function()
      vim.cmd("wshada! " .. vim.fn.fnameescape(shada_file))
      local old = os.time() - 1000
      vim.uv.fs_utime(shada_file, old, old)
      vim.api.nvim_exec_autocmds("SessionLoadPre", {})
      assert.equals(old, vim.fn.getftime(shada_file))
    end)
  end)

  describe("commands", function()
    before_each(function()
      sessman.init()
    end)

    it(":SessionProjectSet <dir> sets the project", function()
      local other = env.root .. "/other"
      vim.fn.mkdir(other, "p")
      vim.cmd("SessionProjectSet " .. vim.fn.fnameescape(other))
      assert.equals(other .. "/", vim.g.sessman_project)
    end)

    it(":SessionProjectSet without args prompts, defaulting to the cwd", function()
      local other = env.root .. "/other"
      vim.fn.mkdir(other, "p")
      local calls = env.stub_input(other)
      vim.cmd("SessionProjectSet")
      assert.equals(vim.fn.getcwd(), calls[1].default)
      assert.equals(other .. "/", vim.g.sessman_project)
    end)

    it(":SessionProjectClear clears the project", function()
      vim.cmd("SessionProjectClear")
      assert.is_nil(vim.g.sessman_project)
    end)

    it(":SessionDelete <name> deletes that session", function()
      local path = env.write_session("gone.vim")
      env.stub_select("Yes")
      vim.cmd("SessionDelete gone.vim")
      assert.equals(0, vim.fn.filereadable(path))
    end)

    it(":SessionSave opens the save form", function()
      vim.cmd("SessionSave")
      assert.is_not_nil(env.find_buf("sessman://session"))
    end)

    it(":SessionSaveCurrent opens the save form when no session is loaded", function()
      vim.cmd("SessionSaveCurrent")
      assert.is_not_nil(env.find_buf("sessman://session"))
    end)

    it(":SessionLoad opens the session list", function()
      vim.cmd("SessionLoad")
      assert.is_not_nil(env.find_buf("sessman://sessions"))
    end)

    it(":SessionInfo and :SessionCurrent toggle the info view", function()
      vim.cmd("SessionInfo")
      assert.is_not_nil(env.find_buf("sessman://info"))
      vim.cmd("SessionCurrent")
      assert.is_nil(env.find_buf("sessman://info"))
    end)

    it(":SessionTmuxSync warns outside tmux", function()
      local orig = vim.env.TMUX
      vim.env.TMUX = nil
      local notes = env.capture_notify()
      vim.cmd("SessionTmuxSync")
      vim.env.TMUX = orig
      assert.is_true(env.notified(notes, "requires running Neovim inside a tmux session", vim.log.levels.WARN))
    end)

    it(":SessionDebugStart / :SessionDebugStop toggle g:sessman_debug", function()
      local orig_print = _G.print
      _G.print = function() end
      vim.cmd("SessionDebugStart")
      local started = vim.g.sessman_debug
      vim.cmd("SessionDebugStop")
      _G.print = orig_print
      assert.is_true(started)
      assert.is_false(vim.g.sessman_debug)
    end)
  end)

  it("debug() prints the configuration, project and session dir", function()
    local out = {}
    local orig_print = _G.print
    _G.print = function(s)
      out[#out + 1] = s
    end
    local ok = pcall(sessman.debug)
    _G.print = orig_print
    assert.is_true(ok)
    local text = table.concat(out, "\n")
    assert.truthy(text:find("Current project: " .. env.project, 1, true))
    assert.truthy(text:find("Session dir: " .. env.session_dir, 1, true))
  end)
end)
