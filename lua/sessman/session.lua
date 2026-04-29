--- lua/sessman/session.lua
--- Session save/load operations

local M = {}

--- Get the current session file path
-- ---@return string
function M.current_session()
  local msg = {}

  if vim.v.this_session == "" then
    table.insert(msg, { "No active session\n", "DiagnosticWarn" })
  else
    table.insert(msg, { "Session: ", "DiagnosticHint" })
    table.insert(msg, { vim.v.this_session .. "\n", "None" })
  end

  if vim.o.shadafile == "" then
    table.insert(msg, { "Global ShaDa file", "DiagnosticWarn" })
  else
    table.insert(msg, { "ShaDa: ", "DiagnosticHint" })
    table.insert(msg, { vim.o.shadafile, "None" })
  end

  vim.api.nvim_echo(msg, false, {})
end

--- Save a session with the given name
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

  -- capture cwd
  local current_dir = old_cwd

  -- save from project root
  vim.fn.chdir(project)

  vim.cmd("silent! mksession! " .. vim.fn.fnameescape(session_file))

  -- read session file
  local lines = vim.fn.readfile(session_file)

  -- persist project + desired cwd
  local project_line = 'let g:sessman_project = "' .. project .. '"'
  local cwd_line = 'let g:sessman_cwd = "' .. current_dir .. '"'

  table.insert(lines, 1, cwd_line)
  table.insert(lines, 1, project_line)

  -- apply cwd after session loads
  table.insert(lines, 'if exists("g:sessman_cwd") | execute "cd " . fnameescape(g:sessman_cwd) | endif')

  -- write updated session file
  vim.fn.writefile(lines, session_file)

  -- update current session
  vim.v.this_session = session_file

  -- save shada file if requested
  local shada_file = dir .. "/" .. name:gsub("%.vim$", "") .. ".shada"
  if opts.shada then
    vim.cmd("wshada! " .. vim.fn.fnameescape(shada_file))
    -- Set shadafile option so future writes go to this session-specific shada
    vim.o.shadafile = shada_file
  end

  -- restore original cwd and options
  vim.fn.chdir(old_cwd)
  vim.o.sessionoptions = old_sessionoptions

  vim.api.nvim_echo({
    { "Saved Session: ", "DiagnosticHint" },
    { session_file, "None" },
  }, false, {})
  if opts.shada then
    vim.api.nvim_echo({
      { "Saved ShaDa: ", "DiagnosticHint" },
      { shada_file, "None" },
    }, false, {})
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

  -- file exists → confirm
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

  -- file does not exist → save directly
  do_save(name, opts)
end

--- Delete a session file
---@param file string Session filename
---@param dir string Directory containing the session
---@param on_complete? function Callback called after interaction (success or cancel)
function M.delete(file, dir, on_complete)
  vim.ui.select({ "No", "Yes" }, {
    prompt = "Delete '" .. file .. "'?",
  }, function(choice)
    -- If they say "Yes", perform the file operations
    if choice == "Yes" then
      local path = dir .. "/" .. file

      -- if currently active session, clear it first
      if vim.v.this_session == path then
        vim.v.this_session = ""
      end

      local success, err = os.remove(path)
      if success then
        vim.api.nvim_echo({
          { "Deleted Session: ", "DiagnosticWarn" },
          { file, "None" },
        }, false, {})
      else
        vim.api.nvim_echo({
          { "Failed to delete session: ", "DiagnosticError" },
          { err or "unknown error", "None" },
        }, false, {})
      end

      local base = file:gsub("%.vim$", "")
      local shada_path = dir .. "/" .. base .. ".shada"
      if vim.fn.filereadable(shada_path) == 1 then
        if vim.o.shadafile == shada_path then
          vim.o.shadafile = ""
        end

        local shada_success, shada_err = os.remove(shada_path)
        if shada_success then
          vim.api.nvim_echo({
            { "Deleted ShaDa: ", "DiagnosticWarn" },
            { base .. ".shada", "None" },
          }, false, {})
        end
      end

      -- if directory is now empty remove it
      local remaining_files = vim.fn.readdir(dir)
      if #remaining_files == 0 then
        vim.fn.delete(dir, "d")
        vim.api.nvim_echo({
          { "Removed empty session directory", "DiagnosticInfo" },
        }, false, {})
      end
    end

    -- ALWAYS notify caller so the picker can be re-opened
    if on_complete then
      on_complete()
    end
  end)
end

return M
