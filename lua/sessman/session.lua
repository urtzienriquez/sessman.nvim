--- lua/sessman/session.lua
--- Session save/load operations

local M = {}

--- Get the current session file path
---@return string
function M.current_session()
  return vim.v.this_session
end

--- Save a session with the given name
---@param name? string Optional session name (defaults to "Session.vim")
function M.save(name)
  local util = require("sessman.util")
  local project_mod = require("sessman.project")
  local cfg = require("sessman.config").get()

  local project = project_mod.get()

  if vim.fn.isdirectory(project) == 0 then
    print("Invalid project path")
    return
  end

  name = (name and name ~= "") and name or "Session.vim"

  local encoded = util.encode_path(project)
  local base = cfg.session_dir
  local dir = base .. encoded

  vim.fn.mkdir(dir, "p")

  local session_file = dir .. "/" .. name

  -- Check if file exists
  if vim.fn.filereadable(session_file) == 1 then
    local choice = vim.fn.confirm("Session '" .. name .. "' already exists. Overwrite?", "&Yes\n&No", 2)

    if choice ~= 1 then
      print("Session not saved")
      return
    end
  end

  local old_cwd = vim.fn.getcwd()
  local old_sessionoptions = vim.o.sessionoptions

  vim.fn.chdir(project)

  vim.cmd("silent! mksession! " .. vim.fn.fnameescape(session_file))

  -- Update current session
  vim.v.this_session = session_file

  -- -- Sync with tmux-resurrect if enabled
  -- if cfg.tmux_integration then
  --   require("sessman.tmux").update_tmux_resurrect_session()
  -- end
  --
  vim.fn.chdir(old_cwd)
  vim.o.sessionoptions = old_sessionoptions

  print("Saved: " .. session_file)
end

return M
