--- lua/sessman/list.lua
--- Fugitive-style persistent session buffer for the current project: single
--- scratch buffer, doubled-letter actions (load/delete/save/project
--- management, e.g. dd/ss like fugitive's cc/dd) instead of fuzzy pickers
--- or global keymaps. Like fugitive's status buffer, this is the ONE thing
--- meant to be bound in user config (e.g. `:SessionLoad`) -- everything
--- else lives as a keymap in here. Rebuilt in place on every action,
--- mirroring the scaffold already used by sessman/ui.lua and
--- sessman/info.lua.

local M = {}

local project_mod = require("sessman.project")
local picker = require("sessman.picker")

local state = {
  buf = nil,
  dir = nil,
  files = nil, -- string[]|nil
  local_session = nil,
  project = "",
  line_to_file = {}, -- 1-indexed line number -> filename, rebuilt every render
}

local ns_id = vim.api.nvim_create_namespace("sessman_list")

--- Build the segment list for the buffer, and the line->file lookup used by
--- the keymaps below. Segments follow sessman/info.lua's convention: each
--- line is a list of { text, hl_group } pairs.
---@return table[][] segments
---@return table<integer,string> line_to_file
local function build()
  local cfg = require("sessman.config").get().info
  local this_session = vim.v.this_session

  local segments = {}
  local line_to_file = {}

  local function push(segs, file)
    segments[#segments + 1] = segs
    if file then
      line_to_file[#segments] = file
    end
  end

  -- No title, header lines back-to-back (no blank gaps), sections omitted
  -- entirely when empty -- mirrors fugitive's actual status buffer exactly
  -- (s:AddHeader/s:AddSection in autoload/fugitive.vim: header lines have
  -- no spacing between them; a section adds a blank line + heading only
  -- when it has entries, otherwise it contributes nothing at all).
  push({ { "Project:  ", "SessmanLabel" }, { state.project, "SessmanValue" } })
  push({ { "Help:     ", "SessmanLabel" }, { "g?", "SessmanValue" } })

  if state.files then
    push({})
    push({ { string.format("Sessions (%d)", #state.files), "SessmanHeading" } })
    for _, file in ipairs(state.files) do
      local path = state.dir .. "/" .. file
      local active = this_session ~= "" and this_session == path
      local icon = active and cfg.active_icon or cfg.past_icon
      local icon_hl = active and cfg.active_highlight or "SessmanComment"
      push({ { icon .. "  ", icon_hl }, { file, "SessmanValue" } }, file)
    end
  end

  return segments, line_to_file
end

--- Re-gather session data and redraw the buffer in place.
local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  state.dir, state.files, state.local_session = picker.get_sessions()
  state.project = project_mod.get()

  local segments, line_to_file = build()
  state.line_to_file = line_to_file

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

--- Resolve the session filename under the cursor, re-derived fresh from
--- the current render every time (no state that can go stale between
--- renders), mirroring fugitive's "always re-inspect the buffer" approach.
---@return string|nil
local function file_under_cursor()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_to_file[lnum]
end

local function load_under_cursor()
  local file = file_under_cursor()
  if file then
    picker.load_session(state.dir .. "/" .. file)
    return
  end
  if not state.files and state.local_session and vim.fn.filereadable(state.local_session) == 1 then
    picker.load_session(state.local_session)
    return
  end
  vim.notify("No session on this line", vim.log.levels.WARN)
end

local function delete_under_cursor()
  local file = file_under_cursor()
  if not file then
    vim.notify("No session on this line", vim.log.levels.WARN)
    return
  end
  require("sessman.session").delete(file, state.dir, render)
end

--- Jump to the "Sessions (N)" heading, fugitive-style section jump
--- (mirrors fugitive's gu/gU/gs/gp/gP/gr, e.g. `s:MapMotion('gs', ...
--- StageJump(v:count, 'Staged'))`).
local function goto_sessions()
  vim.fn.search([[\v^Sessions \(]], "W")
end

--- Jump to the next/previous session entry line. Uses the exact line
--- numbers already recorded in state.line_to_file rather than a text
--- search, since we know precisely which lines are entries.
---@param delta 1|-1
local function jump_entry(delta)
  local candidates = {}
  for lnum in pairs(state.line_to_file) do
    candidates[#candidates + 1] = lnum
  end
  if #candidates == 0 then
    return
  end
  table.sort(candidates)

  local cur = vim.api.nvim_win_get_cursor(0)[1]
  if delta > 0 then
    for _, lnum in ipairs(candidates) do
      if lnum > cur then
        vim.api.nvim_win_set_cursor(0, { lnum, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { candidates[1], 0 }) -- wrap to first
  else
    for i = #candidates, 1, -1 do
      if candidates[i] < cur then
        vim.api.nvim_win_set_cursor(0, { candidates[i], 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { candidates[#candidates], 0 }) -- wrap to last
  end
end

--- Pick a project directory via the configured picker backend. Refresh
--- happens via the SessmanProjectChanged listener registered in M.open(),
--- same as the "cp<Space>"/"cx" command-driven paths below.
local function pick_project()
  require("sessman.backends").call("pick_directory", function(dir)
    if dir then
      project_mod.set(dir)
    end
  end)
end

--- Open the session list, focusing it if already open.
function M.open()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local win = vim.fn.bufwinid(state.buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
      render()
      return
    end
  end

  if vim.o.splitbelow then
    vim.cmd("botright split")
  else
    vim.cmd("topleft split")
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, state.buf)

  pcall(vim.api.nvim_buf_set_name, state.buf, "sessman://sessions")

  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].filetype = "sessman-list"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].buflisted = false
  vim.bo[state.buf].swapfile = false

  render()

  -- Refresh whenever the project changes, regardless of which of the three
  -- paths below caused it (typed command, picker, or clear) -- single
  -- source of truth instead of each path re-rendering itself.
  vim.api.nvim_create_autocmd("User", {
    pattern = "SessmanProjectChanged",
    group = vim.api.nvim_create_augroup("SessmanList", { clear = true }),
    callback = render,
  })

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = state.buf, silent = true, nowait = true, desc = desc })
  end

  map("<CR>", load_under_cursor, "load session under cursor")
  -- Doubled-letter actions, fugitive-style (cc=commit, dd=diff, etc.):
  -- every action below is two keys, except R which fugitive itself also
  -- keeps bare.
  map("dd", delete_under_cursor, "delete session under cursor")
  map("ss", function()
    require("sessman.ui").open()
  end, "save a new session")
  -- Fugitive-style: the key sequence itself ends in <Space> (e.g. fugitive's
  -- own "co<Space>" -> ":Git checkout<Space>"), and the mapping pre-fills
  -- the command line -- including the cwd as an editable default, via the
  -- same <C-R>=expr<CR> trick fugitive uses for dynamic defaults -- rather
  -- than submitting anything. The user edits/accepts and hits <CR>
  -- themselves; :SessionProjectSet's own dir-completion still applies.
  vim.keymap.set("n", "cp<Space>", ":<C-U>SessionProjectSet <C-R>=getcwd()<CR>", {
    buffer = state.buf,
    nowait = true,
    desc = "change project (prefilled with cwd)",
  })
  map("pp", pick_project, "pick project via picker")
  map("cx", project_mod.clear, "clear project")
  map("ii", function()
    require("sessman.info").toggle()
  end, "toggle session info/activity log")
  map("TT", function()
    require("sessman.init").tmux_sync()
  end, "sync tmux-resurrect")
  map("R", render, "refresh")
  map("mq", "<Cmd>close<CR>", "close")
  map("g?", "<Cmd>help sessman-list-maps<CR>", "open help at the maps section")

  -- Navigation, fugitive-style (its status buffer's g-prefix is reserved
  -- entirely for section jumps -- gu/gU/gs/gp/gP/gr -- never actions).
  map("gs", goto_sessions, "go to sessions")
  map("]c", function()
    jump_entry(1)
  end, "next session")
  map("[c", function()
    jump_entry(-1)
  end, "previous session")
end

return M
