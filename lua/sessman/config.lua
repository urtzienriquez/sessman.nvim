--- lua/sessman/config.lua
--- Configuration management for sessman.nvim

local M = {}

---@class SessmanConfig
---@field backend? "fzf"|"telescope"  Picker backend (optional, auto-detected if not set)
---@field session_dir? string  Custom session directory (defaults to stdpath("data")/session/)
---@field project_detection? "auto"|"manual"  How to detect projects
---@field keymaps SessmanKeymapConfig

---@class SessmanKeymapConfig
---@field enabled boolean
---@field save string|false
---@field load string|false
---@field project_set string|false
---@field project_pick string|false
---@field project_clear string|false
---@field current string|false
---@field tmux_sync string|false

---@type SessmanConfig
M.defaults = {
  backend = nil, -- Auto-detect fzf-lua or telescope
  session_dir = nil, -- Will default to vim.fn.stdpath("data") .. "/session/"
  project_detection = "auto", -- Auto-set project on VimEnter to cwd

  keymaps = {
    enabled = true,
    save = "<leader>ms", -- SessionSave
    load = "<leader>ml", -- SessionLoad
    project_set = false, -- SessionProjectSet (no default keymap)
    project_pick = "<leader>mp", -- SessionProjectPick
    project_clear = false, -- SessionProjectClear (no default keymap)
    current = "<leader>mc", -- SessionCurrent
    tmux_sync = "<leader>mt", -- SessionTmuxSync (no default keymap)
  },
}

---@type SessmanConfig?
M.options = nil
local _initialized = false

---@param opts? table
function M.set(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
  _initialized = true

  -- Set default session_dir if not provided
  if not M.options.session_dir then
    M.options.session_dir = vim.fn.stdpath("data") .. "/session/"
  end

  -- Validate backend if provided
  if M.options.backend and M.options.backend ~= "fzf" and M.options.backend ~= "telescope" then
    vim.notify(
      "sessman: unknown backend '"
        .. tostring(M.options.backend)
        .. "'.\n"
        .. "  Valid values: 'fzf', 'telescope', or nil (auto-detect).",
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
    -- Set default session_dir
    if not M.options.session_dir then
      M.options.session_dir = vim.fn.stdpath("data") .. "/session/"
    end
  end
  return M.options
end

--- Detect which picker backend is available
---@return "fzf"|"telescope"|nil
function M.detect_backend()
  local cfg = M.get()

  -- If explicitly configured, use that
  if cfg.backend then
    return cfg.backend
  end

  -- Try to detect
  if pcall(require, "fzf-lua") then
    return "fzf"
  elseif pcall(require, "telescope") then
    return "telescope"
  end

  return nil
end

return M
