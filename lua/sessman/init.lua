--- lua/sessman/init.lua
--- Public API for sessman.nvim

local M = {}

function M.save()
  require("sessman.ui").open()
end

--- Save the currently loaded session in place, prompting to overwrite.
function M.save_current()
  require("sessman.session").save_current()
end

--- Opens the persistent session-list buffer for the current project.
--- The fuzzy-picker flow is still available via
--- require("sessman.picker").pick_session() for anyone who wants it.
function M.load()
  require("sessman.list").open()
end

---@param name? string Optional session name to delete without prompting
function M.delete(name)
  require("sessman.picker").pick_delete(name)
end

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

function M.project_pick()
  require("sessman.picker").pick_project()
end

function M.project_clear()
  require("sessman.project").clear()
end

function M.current()
  require("sessman.session").current_session()
end

function M.info()
  require("sessman.info").toggle()
end

function M.tmux_sync()
  local tmux = require("sessman.tmux")
  if not tmux.is_inside_tmux() then
    vim.notify("tmux-resurrect sync requires running Neovim inside a tmux session", vim.log.levels.WARN)
    return
  end
  tmux.update_tmux_resurrect_session()
end

function M.debug_start()
  vim.g.sessman_debug = true
  print("Sessman debug logging enabled: " .. vim.fn.stdpath("state") .. "/sessman-debug.log")
end

function M.debug_stop()
  vim.g.sessman_debug = false
  print("Sessman debug logging disabled")
end

-- sessman sets no keymaps of its own: everything is a command/Lua
-- function, and it's up to your own config to bind whatever you want,
-- e.g. `vim.keymap.set("n", "<leader>ms", "<Cmd>SessionLoad<CR>")`.
-- The session-list buffer opened by :SessionLoad has its own buffer-local
-- keymaps for the rest of sessman's actions (see lua/sessman/list.lua).

local function create_commands()
  vim.api.nvim_create_user_command("SessionSave", M.save, {})
  vim.api.nvim_create_user_command("SessionSaveCurrent", M.save_current, {})
  vim.api.nvim_create_user_command("SessionLoad", M.load, {})
  vim.api.nvim_create_user_command("SessionDelete", function(opts)
    M.delete(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("SessionProjectSet", function(opts)
    M.project_set(opts.args ~= "" and opts.args or nil)
  end, { nargs = "?", complete = "dir" })
  vim.api.nvim_create_user_command("SessionProjectPick", M.project_pick, {})
  vim.api.nvim_create_user_command("SessionProjectClear", M.project_clear, {})
  vim.api.nvim_create_user_command("SessionCurrent", M.current, {})
  vim.api.nvim_create_user_command("SessionInfo", M.info, {})
  vim.api.nvim_create_user_command("SessionTmuxSync", M.tmux_sync, {})
  vim.api.nvim_create_user_command("SessionDebugStart", M.debug_start, {})
  vim.api.nvim_create_user_command("SessionDebugStop", M.debug_stop, {})
end

local _initialized = false

--- Called by plugin/sessman.lua on VimEnter.
function M.init()
  if _initialized then
    return
  end
  _initialized = true

  local cfg = require("sessman.config").get()

  if cfg.project_detection == "auto" then
    if not vim.g.sessman_project or vim.g.sessman_project == "" then
      vim.g.sessman_project = vim.fn.getcwd()
    end
  end

  create_commands()

  if vim.g.sessman_debug then
    require("sessman.logger").setup()
  end

  local session_group = vim.api.nvim_create_augroup("SessmanSession", { clear = true })

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    group = session_group,
    callback = function()
      local session_file = vim.v.this_session
      if session_file == "" then
        return
      end

      -- Session files fire this once per window; only handle the first fire
      local info = require("sessman.info")
      if not info.is_new_load("Post", session_file) then
        return
      end

      info.add("Loaded Session", session_file, "DiagnosticHint")

      local shada_file = session_file:gsub("%.vim$", "") .. ".shada"
      if vim.fn.filereadable(shada_file) == 1 then
        vim.o.shadafile = shada_file
        vim.cmd("rshada! " .. vim.fn.fnameescape(shada_file))

        info.add("Loaded ShaDa", shada_file, "DiagnosticHint")
      else
        vim.o.shadafile = ""
      end
    end,
  })

  -- Only writes if the current session has an associated shada file that is
  -- also the one currently in use.
  vim.api.nvim_create_autocmd("SessionLoadPre", {
    group = session_group,
    callback = function()
      local session_file = vim.v.this_session
      if session_file == "" then
        return
      end

      -- Session files fire this once per window; only handle the first fire
      if not require("sessman.info").is_new_load("Pre", session_file) then
        return
      end

      local shada_file = session_file:gsub("%.vim$", "") .. ".shada"
      if
        vim.fn.filereadable(shada_file) == 1
        and vim.fn.fnamemodify(vim.o.shadafile, ":p") == vim.fn.fnamemodify(shada_file, ":p")
      then
        vim.cmd("wshada!")
      end
    end,
  })

  require("sessman.highlights").setup()

  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      require("sessman.highlights").setup()
    end,
  })
end

---@param opts? table
function M.setup(opts)
  require("sessman.config").set(opts)

  if not _initialized then
    M.init()
  end
end

function M.debug()
  local cfg = require("sessman.config").get()
  print("sessman configuration:")
  print(vim.inspect(cfg))
  print("\nCurrent project: " .. (vim.g.sessman_project or "not set"))
  print("Backend: " .. (cfg.backend or "auto"))
  print("Session dir: " .. cfg.session_dir)
end

return M
