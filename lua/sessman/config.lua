--- lua/sessman/config.lua
--- Configuration management for sessman.nvim

local M = {}

---@class SessmanConfig
---@field backend? "fzf"|"telescope"|"minipick"|"snacks"  Picker backend (optional, auto-detected if not set)
---@field session_dir? string  Custom session directory (defaults to stdpath("data")/session/)
---@field project_detection? "auto"|"manual"  How to detect projects
---@field info SessmanInfoConfig

---@class SessmanInfoConfig
---@field active_icon string  Marker shown on the currently loaded session/shada
---@field past_icon string  Marker shown on past loaded session/shada entries
---@field active_highlight string  Highlight group for the active marker

-- No keymaps.* config: sessman sets no keymaps of its own -- bind
-- whatever you want to the commands it provides.

---@type SessmanConfig
M.defaults = {
  backend = nil, -- auto-detect fzf-lua, telescope, minipick or snacks
  session_dir = nil, -- defaults to vim.fn.stdpath("data") .. "/session/"
  project_detection = "auto",

  info = {
    active_icon = "●",
    past_icon = "○",
    active_highlight = "DiagnosticOk",
  },
}

---@type SessmanConfig?
M.options = nil
local _initialized = false

--- Session paths are built as `session_dir .. encoded_project`, so the
--- directory must be expanded and end with exactly one slash.
---@param dir? string
---@return string
local function normalize_session_dir(dir)
  if not dir or dir == "" then
    dir = vim.fn.stdpath("data") .. "/session"
  end
  return (vim.fn.expand(dir):gsub("/+$", "")) .. "/"
end

---@param opts? table
function M.set(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
  _initialized = true

  M.options.session_dir = normalize_session_dir(M.options.session_dir)

  if
    M.options.backend
    and M.options.backend ~= "fzf"
    and M.options.backend ~= "minipick"
    and M.options.backend ~= "snacks"
    and M.options.backend ~= "telescope"
  then
    vim.notify(
      "sessman: unknown backend '"
        .. tostring(M.options.backend)
        .. "'.\n"
        .. "  Valid values: 'fzf', 'telescope', 'minipick', 'snacks' or nil (auto-detect).",
      vim.log.levels.WARN
    )
    M.options.backend = nil
  end
end

---@return SessmanConfig
function M.get()
  if not _initialized then
    M.options = vim.deepcopy(M.defaults)
    _initialized = true
    M.options.session_dir = normalize_session_dir(M.options.session_dir)
  end
  return M.options
end

--- Detect which picker backend is available
---@return "fzf"|"telescope"|"minipick"|"snacks"|nil
function M.detect_backend()
  local backend = M.get().backend
  if backend then
    return backend
  end

  if pcall(require, "fzf-lua") then
    return "fzf"
  elseif pcall(require, "telescope") then
    return "telescope"
  elseif pcall(require, "mini.pick") then
    return "minipick"
  elseif pcall(require, "snacks") then
    return "snacks"
  end

  return nil
end

return M
