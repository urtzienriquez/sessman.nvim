--- lua/sessman/info.lua
--- Status window for sessman.nvim (ConformInfo-style)
--- Shows the current session, ShaDa and project state plus a log of
--- recent activity instead of transient echo/notify messages.

local M = {}

local state = {
  buf = nil,
  win = nil,
  events = {}, -- { { kind, text, hl }, ... } newest first
}

local ns_id = vim.api.nvim_create_namespace("sessman_info")
local MAX_EVENTS = 15

--- Push an event into the activity log and refresh the window if open
---@param kind string Prefix shown for the event
---@param text string Event description
---@param hl? string Highlight group for the event line
function M.add(kind, text, hl)
  table.insert(state.events, 1, { kind = kind, text = text, hl = hl or "SessmanValue" })
  if #state.events > MAX_EVENTS then
    table.remove(state.events)
  end
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.render()
  end
end

--- Build the window content as a list of lines, each a list of
--- { text, hl_group } segments
---@return table[][]
local function build_lines()
  local project = require("sessman.project").get()

  local session = vim.v.this_session
  local shada = vim.o.shadafile

  local lines = {}

  lines[#lines + 1] = { { "Sessman", "SessmanTitle" } }
  lines[#lines + 1] = {}

  if session == "" then
    lines[#lines + 1] = { { "Session:  ", "SessmanLabel" }, { "(none)", "DiagnosticWarn" } }
  else
    lines[#lines + 1] = { { "Session:  ", "SessmanLabel" }, { session, "SessmanValue" } }
  end

  if shada == "" then
    lines[#lines + 1] = { { "ShaDa:    ", "SessmanLabel" }, { "(global)", "DiagnosticWarn" } }
  else
    local shada_display = shada
    if vim.fn.filereadable(shada) == 0 then
      shada_display = shada .. " (not found)"
    end
    lines[#lines + 1] = { { "ShaDa:    ", "SessmanLabel" }, { shada_display, "SessmanValue" } }
  end

  lines[#lines + 1] = { { "Project:  ", "SessmanLabel" }, { project, "SessmanValue" } }

  lines[#lines + 1] = {}
  lines[#lines + 1] = { { string.rep("─", 40), "SessmanSeparator" } }

  if #state.events == 0 then
    lines[#lines + 1] = { { "No recent activity", "SessmanComment" } }
  else
    for _, ev in ipairs(state.events) do
      local segs = { { ev.kind, "SessmanLabel" } }
      if ev.text and ev.text ~= "" then
        segs[#segs + 1] = { "  " .. ev.text, ev.hl }
      end
      lines[#lines + 1] = segs
    end
  end

  return lines
end

--- Render the current state into the info buffer
function M.render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local segments = build_lines()

  local lines = {}
  for _, segs in ipairs(segments) do
    local text = {}
    for _, seg in ipairs(segs) do
      text[#text + 1] = seg[1]
    end
    lines[#lines + 1] = table.concat(text)
  end

  vim.bo[state.buf].modifiable = true
  vim.bo[state.buf].readonly = false
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].readonly = true

  vim.api.nvim_buf_clear_namespace(state.buf, ns_id, 0, -1)
  for row, segs in ipairs(segments) do
    local col = 0
    for _, seg in ipairs(segs) do
      if seg[2] then
        vim.api.nvim_buf_set_extmark(state.buf, ns_id, row - 1, col, {
          end_col = col + #seg[1],
          hl_group = seg[2],
        })
      end
      col = col + #seg[1]
    end
  end

  -- keep the window sized to the content
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    local cfg = M.float_config(segments)
    vim.api.nvim_win_set_config(state.win, cfg)
  end
end

--- Compute the floating window config
---@param segments? table[][] Pre-built lines to measure
function M.float_config(segments)
  segments = segments or build_lines()

  local width = 60
  for _, segs in ipairs(segments) do
    local len = 0
    for _, seg in ipairs(segs) do
      len = len + #seg[1]
    end
    if len > width then
      width = len
    end
  end

  local content_width = math.min(width + 2, vim.o.columns - 4)
  local content_height = math.min(#segments + 2, vim.o.lines - 4)

  return {
    relative = "editor",
    row = math.max(0, math.floor((vim.o.lines - content_height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - content_width) / 2)),
    width = content_width,
    height = content_height,
    style = "minimal",
    border = "rounded",
  }
end

--- Close the info window and wipe its buffer
function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
end

--- Open the info window, focusing it if already open
function M.open()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    M.render()
    return state.win
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "sessman-info"
  vim.api.nvim_buf_set_name(state.buf, "sessman://info")

  M.render()

  local opts = { buffer = state.buf, silent = true, nowait = true }
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
  vim.keymap.set("n", "g?", "<Cmd>help sessman-info<CR>", opts)

  state.win = vim.api.nvim_open_win(state.buf, true, M.float_config())
  return state.win
end

--- Toggle the info window open/closed
function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

return M