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

--- get list of unsaved (relevant) buffers
local function get_unsaved_buffers()
  local unsaved = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].modified and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
      local name = vim.api.nvim_buf_get_name(buf)

      if name == "" then
        name = "[No Name]"
      else
        name = vim.fn.fnamemodify(name, ":~:.")
      end

      table.insert(unsaved, name)
    end
  end

  return unsaved
end

--- load a session safely
local function load_session(session_file)
  -- abort if unsaved changes exist
  local unsaved = get_unsaved_buffers()

  if #unsaved > 0 then
    vim.notify(
      "Unsaved changes in:\n" .. table.concat(unsaved, "\n"),
      vim.log.levels.WARN,
      { title = "Unsaved buffers" }
    )
    return false
  end

  vim.api.nvim_exec_autocmds("SessionLoadPre", {})

  -- clean current state
  vim.cmd.tabonly({ mods = { silent = true } })
  vim.cmd("silent bufdo bwipeout")

  -- load session
  local ok, err = pcall(vim.cmd, "silent source " .. vim.fn.fnameescape(session_file))

  if not ok then
    vim.notify("Failed to load session: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  vim.api.nvim_exec_autocmds("SessionLoadPost", {})
  return true
end

--- pick and load a session
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

    vim.notify("No sessions for this project: " .. dir, vim.log.levels.WARN)
    return
  end

  -- Read session files
  local files = vim.fn.readdir(dir)
  files = vim.tbl_filter(function(file)
    return file:match("%.vim$")
  end, files)

  if not files or #files == 0 then
    if vim.fn.filereadable(local_session) == 1 then
      load_session(local_session)
      return
    end

    vim.notify("No sessions found in: " .. dir, vim.log.levels.WARN)
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
