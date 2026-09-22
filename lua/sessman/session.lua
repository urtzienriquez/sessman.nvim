--- lua/sessman/session.lua
--- Session save/load operations

local M = {}

function M.current_session()
  require("sessman.info").toggle()
end

---@param name? string Optional session name (defaults to "Session.vim")
---@param opts? table Optional settings { shada = boolean }
local function do_save(name, opts)
  local util = require("sessman.util")
  local project_mod = require("sessman.project")
  local cfg = require("sessman.config").get()

  opts = opts or {}
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

  local old_cwd = vim.fn.getcwd()
  local old_sessionoptions = vim.o.sessionoptions
  local current_dir = old_cwd

  vim.fn.chdir(project)

  vim.cmd("silent! mksession! " .. vim.fn.fnameescape(session_file))

  local lines = vim.fn.readfile(session_file)

  -- Persist project + desired cwd, and restore cwd on load (mksession
  -- itself records the project root as cwd, not the dir the user was in).
  local project_line = 'let g:sessman_project = "' .. project .. '"'
  local cwd_line = 'let g:sessman_cwd = "' .. current_dir .. '"'

  table.insert(lines, 1, cwd_line)
  table.insert(lines, 1, project_line)
  table.insert(lines, 'if exists("g:sessman_cwd") | execute "cd " . fnameescape(g:sessman_cwd) | endif')

  vim.fn.writefile(lines, session_file)

  vim.v.this_session = session_file

  local shada_file = dir .. "/" .. name:gsub("%.vim$", "") .. ".shada"
  if opts.shada then
    vim.cmd("wshada! " .. vim.fn.fnameescape(shada_file))
    vim.o.shadafile = shada_file
  end

  vim.fn.chdir(old_cwd)
  vim.o.sessionoptions = old_sessionoptions

  local info = require("sessman.info")
  info.add("Saved Session", session_file, "DiagnosticHint")
  if opts.shada then
    info.add("Saved ShaDa", shada_file, "DiagnosticHint")
  end
end

function M.save(name, opts)
  local util = require("sessman.util")
  local project_mod = require("sessman.project")
  local cfg = require("sessman.config").get()

  opts = opts or {}
  local project = project_mod.get()

  if vim.fn.isdirectory(project) == 0 then
    print("Invalid project path")
    return
  end

  name = (name and name ~= "") and name or "Session.vim"

  local encoded = util.encode_path(project)
  local dir = cfg.session_dir .. encoded
  local session_file = dir .. "/" .. name

  if vim.fn.filereadable(session_file) == 1 then
    vim.ui.select({ "No", "Yes" }, {
      prompt = "Session '" .. name .. "' already exists. Overwrite?",
    }, function(choice)
      if choice == "Yes" then
        do_save(name, opts)
      else
        print("Session not saved")
      end
    end)
    return
  end

  do_save(name, opts)
end

---@param file string Session filename
---@param dir string Directory containing the session
---@param on_complete? function Callback called after interaction (success or cancel)
function M.delete(file, dir, on_complete)
  vim.ui.select({ "No", "Yes" }, {
    prompt = "Delete '" .. file .. "'?",
  }, function(choice)
    if choice == "Yes" then
      local path = dir .. "/" .. file

      if vim.v.this_session == path then
        vim.v.this_session = ""
      end

      local success, err = os.remove(path)
      if success then
        require("sessman.info").add("Deleted Session", file, "DiagnosticWarn")
      else
        vim.notify("Failed to delete session: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end

      local base = file:gsub("%.vim$", "")
      local shada_path = dir .. "/" .. base .. ".shada"
      if vim.fn.filereadable(shada_path) == 1 then
        if vim.o.shadafile == shada_path then
          vim.o.shadafile = ""
        end

        local shada_success, shada_err = os.remove(shada_path)
        if shada_success then
          require("sessman.info").add("Deleted ShaDa", base .. ".shada", "DiagnosticWarn")
        else
          vim.notify("Failed to delete ShaDa: " .. (shada_err or "unknown error"), vim.log.levels.WARN)
        end
      end

      local remaining_files = vim.fn.readdir(dir)
      if #remaining_files == 0 then
        vim.fn.delete(dir, "d")
        require("sessman.info").add("Removed empty directory", dir, "DiagnosticInfo")
      end
    end

    -- Notify unconditionally (even on cancel) so the caller can re-open its view.
    if on_complete then
      on_complete()
    end
  end)
end

return M
