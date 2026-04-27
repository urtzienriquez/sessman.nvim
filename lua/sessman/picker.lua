--- lua/sessman/picker.lua
--- Session and project picker using the configured backend

local M = {}

local project = require("sessman.project")
local util = require("sessman.util")
local backends = require("sessman.backends")

--- Pick a project directory
function M.pick_project()
  backends.call("pick_directory", function(dir)
    if not dir then
      return
    end
    project.set(dir)
  end)
end

local function has_unsaved_buffers()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      return true
    end
  end
  return false
end

--- Pick and load a session
local function load_session(session_file)
  -- abort if unsaved changes exist
  if has_unsaved_buffers() then
    vim.notify("Unsaved changes detected. Refusing to switch session.", vim.log.levels.WARN)
    return false
  end

  -- clean current state
  vim.cmd.tabonly({ mods = { silent = true } })
  vim.cmd("bufdo bwipeout")

  -- load session
  local ok, err = pcall(vim.cmd, "silent source " .. vim.fn.fnameescape(session_file))

  if not ok then
    vim.notify("Failed to load session: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  print("Loaded session:\n" .. session_file)
  return true
end

function M.pick_session()
  local current_project = project.get()
  local encoded = util.encode_path(current_project)

  local cfg = require("sessman.config").get()
  local base = cfg.session_dir
  local dir = base .. encoded
  local local_session = current_project .. "/Session.vim"

  -- check if session directory exists
  if vim.fn.isdirectory(dir) == 0 then
    if vim.fn.filereadable(local_session) == 1 then
      load_session(local_session)
      return
    end

    print("No sessions for this project: " .. dir)
    return
  end

  -- Read session files
  local files = vim.fn.readdir(dir)

  if not files or #files == 0 then
    if vim.fn.filereadable(local_session) == 1 then
      load_session(local_session)
      return
    end

    print("No sessions found in: " .. dir)
    return
  end

  -- Sort by modification time
  util.sort_by_mtime(dir, files)

  -- Use backend to pick session
  backends.call("pick_session", files, dir, function(file)
    if not file then
      return
    end

    local session_file = dir .. "/" .. file
    load_session(session_file)
  end)
end

return M
