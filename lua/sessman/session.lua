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
  local base = cfg.session_dir
  local dir = base .. encoded

  vim.fn.mkdir(dir, "p")

  local session_file = dir .. "/" .. name

  -- check if file exists
  if vim.fn.filereadable(session_file) == 1 then
    local choice = vim.fn.confirm("Session '" .. name .. "' already exists. Overwrite?", "&Yes\n&No", 2)

    if choice ~= 1 then
      print("Session not saved")
      return
    end
  end

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

return M
