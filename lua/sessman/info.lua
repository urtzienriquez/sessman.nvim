--- lua/sessman/info.lua
--- Status window for sessman.nvim
--- Shows the current session, ShaDa and project state plus a log of
--- recent activity instead of transient echo/notify messages.
--- Opens in a new tab (like :checkhealth) as a scratch buffer.

local M = {}

local state = {
  buf = nil,
  events = {}, -- { { kind, text, hl }, ... } newest first
}

local ns_id = vim.api.nvim_create_namespace("sessman_info")
local MAX_EVENTS = 15

--- Dedupe guard for SessionLoadPre/Post autocmds.
--- Session files fire these events once per window (via :doautoall), so this
--- returns true only for the first fire of a load and for genuinely new loads.
--- Each event type keeps its own entry so the first SessionLoadPre and the
--- first SessionLoadPost of the same load are both honored.
local load_guard = {}
local LOAD_BURST_NS = 500e6 -- 500ms, covers the whole burst from one :source

---@param event "Pre"|"Post"
---@param path string this_session path
---@return boolean true if this is not a repeated synchronous fire of the same load
function M.is_new_load(event, path)
  local entry = load_guard[event]
  local now = vim.uv.hrtime()
  if entry and entry.path == path and (now - entry.mono) < LOAD_BURST_NS then
    return false
  end
  load_guard[event] = { path = path, mono = now }
  return true
end

---@param kind string Prefix shown for the event
---@param text string Event description
---@param hl? string Highlight group for the event line
function M.add(kind, text, hl)
  table.insert(state.events, 1, { kind = kind, text = text, hl = hl or "SessmanValue" })
  if #state.events > MAX_EVENTS then
    table.remove(state.events)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    M.render()
  end
end

---@param ev table { kind, text, hl }
---@param current_session string
---@param current_shada string
---@return table segments
local function event_segments(ev, current_session, current_shada)
  local is_loaded = ev.kind == "Loaded Session" or ev.kind == "Loaded ShaDa"

  if not is_loaded then
    local segs = { { ev.kind, "SessmanLabel" } }
    if ev.text and ev.text ~= "" then
      segs[#segs + 1] = { "  " .. ev.text, ev.hl }
    end
    return segs
  end

  local current_path = ev.kind == "Loaded Session" and current_session or current_shada
  local active = current_path ~= "" and ev.text == current_path

  local cfg = require("sessman.config").get().info
  local icon = active and cfg.active_icon or cfg.past_icon
  local icon_hl = active and cfg.active_highlight or "SessmanComment"

  return {
    { icon .. "  ", icon_hl },
    { ev.kind .. "  ", "SessmanLabel" },
    { ev.text, ev.hl },
  }
end

--- Build the window content as a list of lines, each a list of
--- { text, hl_group } segments
---@return table[][]
local function build_lines()
  local project = require("sessman.project").get()

  local session = vim.v.this_session
  local shada = vim.o.shadafile

  local lines = {}

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
  lines[#lines + 1] = { { "Help:     ", "SessmanLabel" }, { "g?", "SessmanValue" } }

  lines[#lines + 1] = {}
  lines[#lines + 1] = { { string.rep("─", 40), "SessmanSeparator" } }

  if #state.events == 0 then
    lines[#lines + 1] = { { "No recent activity", "SessmanComment" } }
  else
    for _, ev in ipairs(state.events) do
      lines[#lines + 1] = event_segments(ev, session, shada)
    end
  end

  return lines
end

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
end

---@return integer bufnr
local function create_buffer()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].filetype = "sessman-info"
  vim.api.nvim_buf_set_name(state.buf, "sessman://info")

  M.render()

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = state.buf, silent = true, nowait = true, desc = desc })
  end
  map("mq", M.close, "close")
  map("g?", "<Cmd>help sessman-info-maps<CR>", "open help at the maps section")

  return state.buf
end

function M.close()
  local buf = state.buf
  state.buf = nil
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

--- Open the info view in a new tab, focusing it if already open.
function M.open()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local wins = vim.fn.win_findbuf(state.buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      M.render()
      return vim.api.nvim_get_current_win()
    end
  end

  local buf = create_buffer()
  vim.cmd.sbuffer { buf, mods = { tab = vim.api.nvim_tabpage_get_number(0) } }
  return vim.api.nvim_get_current_win()
end

function M.toggle()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) and #vim.fn.win_findbuf(state.buf) > 0 then
    M.close()
  else
    M.open()
  end
end

return M
