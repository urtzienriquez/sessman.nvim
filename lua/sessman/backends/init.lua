--- lua/sessman/backends/init.lua
--- Backend registry for picker implementations

local M = {}

---@type table<string, table>
local _registry = {}

--- Register a backend by name
---@param name string
---@param backend table
function M.register(name, backend)
  _registry[name] = backend
end

--- Get the active backend, loading it lazily if needed
---@return table|nil
function M.get()
  local name = require("sessman.config").detect_backend()
  if not name then
    return nil
  end

  -- Lazy-load built-in backends on first access
  if not _registry[name] then
    local ok, mod = pcall(require, "sessman.backends." .. name)
    if ok then
      _registry[name] = mod
    else
      vim.notify("sessman: backend '" .. name .. "' could not be loaded.\n" .. tostring(mod), vim.log.levels.ERROR)
      return nil
    end
  end

  return _registry[name]
end

--- Call a function on the active backend
---@param fn_name string
---@param ... any
function M.call(fn_name, ...)
  local b = M.get()
  if not b then
    vim.notify("sessman: no picker backend found. Install fzf-lua or telescope.nvim.", vim.log.levels.WARN)
    return
  end

  if type(b[fn_name]) ~= "function" then
    vim.notify(
      "sessman: backend '"
        .. tostring(require("sessman.config").detect_backend())
        .. "' does not support '"
        .. fn_name
        .. "'.",
      vim.log.levels.WARN
    )
    return
  end

  b[fn_name](...)
end

return M
