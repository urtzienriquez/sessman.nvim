local M = {}

local project = require("sessman.project")
local util = require("sessman.util")

-- choose backend (for future extensibility)
local backend = require("sessman.backends.fzf")

function M.pick_project()
  backend.pick_directory(function(dir)
    if not dir then
      return
    end
    require("sessman.project").set(dir)
  end)
end

function M.pick_session()
  local current_project = project.get()
  local encoded = util.encode_path(current_project)

  local base = vim.fn.stdpath("data") .. "/session/"
  local dir = base .. encoded
  local local_session = current_project .. "/Session.vim"

  local function load_session(session_file)
    local ok, err = pcall(vim.cmd, "silent source " .. vim.fn.fnameescape(session_file))
    if not ok then
      vim.notify("Failed to load session: " .. tostring(err), vim.log.levels.ERROR)
      return false
    end

    print("Loaded session:\n" .. session_file)
    return true
  end

  if vim.fn.isdirectory(dir) == 0 then
    if vim.fn.filereadable(local_session) == 1 then
      load_session(local_session)
      return
    end

    print("No sessions for this project: " .. dir)
    return
  end

  local files = vim.fn.readdir(dir)

  if not files or #files == 0 then
    if vim.fn.filereadable(local_session) == 1 then
      load_session(local_session)
      return
    end

    print("No sessions found in: " .. dir)
    return
  end

  util.sort_by_mtime(dir, files)

  backend.pick_session(files, dir, function(file)
    if not file then
      return
    end

    local session_file = dir .. "/" .. file
    load_session(session_file)
  end)
end

return M
