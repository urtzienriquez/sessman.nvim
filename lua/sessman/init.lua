--- lua/sessman/init.lua
--- Public API for sessman.nvim

local M = {}

-- ─────────────────────────────────────────────────────────────
-- Public API functions
-- ─────────────────────────────────────────────────────────────

--- Save the current session
function M.save()
  require("sessman.ui").open()
end

--- Load a session via picker
function M.load()
  require("sessman.picker").pick_session()
end

--- Set the project directory
---@param path? string
function M.project_set(path)
  if path then
    require("sessman.project").set(path)
  else
    vim.ui.input({ prompt = "Project directory: ", default = vim.fn.getcwd(), completion = "dir" }, function(input)
      if input then
        require("sessman.project").set(input)
      end
    end)
  end
end

--- Pick a project directory using the picker
function M.project_pick()
  require("sessman.picker").pick_project()
end

--- Clear the current project setting
function M.project_clear()
  require("sessman.project").clear()
end

--- Show the current session file path
function M.current()
  require("sessman.session").current_session()
end

--- Sync session with tmux-resurrect
function M.tmux_sync()
  require("sessman.tmux").update_tmux_resurrect_session()
end

--- Enable debug logging
function M.debug_start()
  vim.g.sessman_debug = true
  print("Sessman debug logging enabled: " .. vim.fn.stdpath("state") .. "/sessman-debug.log")
end

--- Disable debug logging
function M.debug_stop()
  vim.g.sessman_debug = false
  print("Sessman debug logging disabled")
end

-- ─────────────────────────────────────────────────────────────
-- Keymaps
-- ─────────────────────────────────────────────────────────────

local function set_keymaps()
  local km = require("sessman.config").get().keymaps
  if not km.enabled then
    return
  end

  local function map(lhs, rhs, desc)
    if lhs then
      vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
    end
  end

  map(km.save, M.save, "sessman: save session")
  map(km.load, M.load, "sessman: load session")
  map(km.project_set, M.project_set, "sessman: set project directory")
  map(km.project_pick, M.project_pick, "sessman: pick project directory")
  map(km.project_clear, M.project_clear, "sessman: clear project")
  map(km.current, M.current, "sessman: show current session")
  map(km.tmux_sync, M.tmux_sync, "sessman: sync tmux-resurrect")
end

-- ─────────────────────────────────────────────────────────────
-- Commands
-- ─────────────────────────────────────────────────────────────

local function create_commands()
  vim.api.nvim_create_user_command("SessionSave", M.save, {})
  vim.api.nvim_create_user_command("SessionLoad", M.load, {})
  vim.api.nvim_create_user_command("SessionProjectSet", function(opts)
    M.project_set(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", complete = "dir" })
  vim.api.nvim_create_user_command("SessionProjectPick", M.project_pick, {})
  vim.api.nvim_create_user_command("SessionProjectClear", M.project_clear, {})
  vim.api.nvim_create_user_command("SessionCurrent", M.current, {})
  vim.api.nvim_create_user_command("SessionTmuxSync", M.tmux_sync, {})
  vim.api.nvim_create_user_command("SessionDebugStart", M.debug_start, {})
  vim.api.nvim_create_user_command("SessionDebugStop", M.debug_stop, {})
end

-- ─────────────────────────────────────────────────────────────
-- Initialization
-- ─────────────────────────────────────────────────────────────

local _initialized = false

--- Initialize sessman (called by plugin/sessman.lua on VimEnter)
function M.init()
  if _initialized then
    return
  end
  _initialized = true

  local cfg = require("sessman.config").get()

  -- Set initial project if auto-detection is enabled
  if cfg.project_detection == "auto" then
    if not vim.g.sessman_project or vim.g.sessman_project == "" then
      vim.g.sessman_project = vim.fn.getcwd()
    end
  end

  -- Create user commands
  create_commands()

  -- Set up keymaps
  set_keymaps()

  -- Initialize logger if debug mode was previously enabled
  if vim.g.sessman_debug then
    require("sessman.logger").setup()
  end

  -- Notify on SessionLoadPost about session loaded
  -- also auto-load associated shada file and notify
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      local session_file = vim.v.this_session
      if session_file == "" then
        return
      end

      vim.api.nvim_echo({
        { "Session loaded: ", "DiagnosticHint" },
        { session_file, "None" },
      }, false, {})

      local shada_file = session_file:gsub("%.vim$", "") .. ".shada"
      if vim.fn.filereadable(shada_file) == 1 then
        vim.o.shadafile = shada_file
        vim.cmd("rshada! " .. vim.fn.fnameescape(shada_file))

        vim.api.nvim_echo({
          { "ShaDa loaded: ", "DiagnosticHint" },
          { shada_file, "None" },
        }, false, {})
      end
    end,
  })

  -- set highlight groups
  require("sessman.highlights").setup()

  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      require("sessman.highlights").setup()
    end,
  })
end

--- Setup function for user configuration
---@param opts? table
function M.setup(opts)
  require("sessman.config").set(opts)

  if not _initialized then
    M.init()
  end
end

--- Debug helper to show current configuration
function M.debug()
  local cfg = require("sessman.config").get()
  print("sessman configuration:")
  print(vim.inspect(cfg))
  print("\nCurrent project: " .. (vim.g.sessman_project or "not set"))
  print("Backend: " .. (cfg.backend or "auto"))
  print("Session dir: " .. cfg.session_dir)
end

return M
