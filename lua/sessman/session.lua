local M = {}

function M.save(name)
  local util = require("sessman.util")
  local project_mod = require("sessman.project")

  local project = project_mod.get()

  if vim.fn.isdirectory(project) == 0 then
    print("Invalid project path")
    return
  end

  name = (name and name ~= "") and name or "Session.vim"

  local encoded = util.encode_path(project)
  local base = vim.fn.stdpath("data") .. "/session/"
  local dir = base .. encoded

  vim.fn.mkdir(dir, "p")

  local session_file = dir .. "/" .. name

  -- check if file exists
  if vim.fn.filereadable(session_file) == 1 then
    local choice = vim.fn.confirm(
      "Session '" .. name .. "' already exists. Overwrite?",
      "&Yes\n&No",
      2
    )

    if choice ~= 1 then
      print("Session not saved")
      return
    end
  end

  local old_cwd = vim.fn.getcwd()
  local old_sessionoptions = vim.o.sessionoptions

  vim.fn.chdir(project)

  vim.cmd("silent! mksession! " .. vim.fn.fnameescape(session_file))

  -- update current session
  vim.v.this_session = session_file

  update_tmux_resurrect_session(session_file)

  vim.fn.chdir(old_cwd)
  vim.o.sessionoptions = old_sessionoptions

  print("Saved: " .. session_file)
end

return M
