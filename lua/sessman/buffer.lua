--- The sessman://sessions buffer, in the spirit of fugitive's summary buffer.

local M = {}

local api, fn = vim.api, vim.fn

M.name = "sessman://sessions"

---@type table<integer, { entries: table<integer, sessman.Session>, groups: integer[] }>
local state = {}

local function ago(t)
  local d = os.time() - t
  for _, unit in ipairs({ { 86400, "d" }, { 3600, "h" }, { 60, "m" } }) do
    if d >= unit[1] then
      return ("%d%s ago"):format(math.floor(d / unit[1]), unit[2])
    end
  end
  return "just now"
end

---@param s sessman.Session
local function details(s)
  local out = { s.current and "current" or nil }
  if s.unmanaged then
    return s.current and "current" or "plain nvim"
  end
  out[#out + 1] = s.saved and ("saved " .. ago(s.mtime or os.time())) or "never saved"
  if s.running and s.cwd and s.cwd ~= s.project then
    local rel = s.project and vim.fs.relpath(s.project, s.cwd)
    out[#out + 1] = "in " .. (rel and (rel .. "/") or fn.fnamemodify(s.cwd, ":~"))
  end
  return table.concat(out, ", ")
end

local function pad(text, width)
  return text .. (" "):rep(width - fn.strdisplaywidth(text))
end

--- This nvim under the header while it isn't a session, then sections by
--- state, like fugitive's Untracked/Unstaged/Staged; inside them, sessions
--- are grouped by project (the one you are in first).
---@param buf integer
function M.render(buf)
  local sessman = require("sessman")
  local sessions = sessman.list()
  local here = sessman.here(sessions)

  local cur
  local sections = {
    { title = "Running", list = {} },
    { title = "Saved", list = {} },
    { title = "Unnamed nvim", list = {} },
  }
  for _, s in ipairs(sessions) do
    if s.current and s.unmanaged then
      cur = s -- a plain nvim: shown under the header until it's saved
    else
      table.insert(sections[s.unmanaged and 3 or s.running and 1 or 2].list, s)
    end
  end

  local function rank(s)
    return s.project == here and 0 or s.project and 1 or 2
  end
  local function before(a, b)
    if rank(a) ~= rank(b) then
      return rank(a) < rank(b)
    elseif a.project ~= b.project then
      return a.project < b.project
    end
    return a.name < b.name
  end

  local lines = {
    "Session: " .. (sessman.current() or { name = "none" }).name,
    "Project: " .. fn.fnamemodify(here, ":~"),
    "Help:    g?",
  }
  local st = { entries = {}, groups = {} }
  if cur then
    lines[#lines + 1] = ""
    lines[#lines + 1] = fn.fnamemodify(cur.name, ":~") .. "  " .. details(cur)
    st.entries[#lines] = cur
  end
  for _, section in ipairs(sections) do
    if #section.list > 0 then
      table.sort(section.list, before)
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("%s (%d)"):format(section.title, #section.list)
      st.groups[#st.groups + 1] = #lines

      -- A tree: each project's full path, its sessions indented below it.
      -- Unnamed nvims are listed directly, by working directory.
      local width = 0
      for _, s in ipairs(section.list) do
        width = math.max(width, fn.strdisplaywidth(s.unmanaged and fn.fnamemodify(s.name, ":~") or s.name))
      end
      local prev = {} -- no project yet
      for _, s in ipairs(section.list) do
        local indent, name = "    ", s.name
        if s.unmanaged then
          indent, name = "  ", fn.fnamemodify(s.name, ":~")
        elseif s.project ~= prev then
          prev = s.project
          lines[#lines + 1] = "  " .. (s.project and fn.fnamemodify(s.project, ":~") or "global")
        end
        lines[#lines + 1] = ((indent .. pad(name, width) .. "  " .. details(s)):gsub("%s+$", ""))
        st.entries[#lines] = s
      end
    end
  end
  state[buf] = st

  local view = fn.winsaveview()
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  if api.nvim_get_current_buf() == buf then
    fn.winrestview(view)
  end
end

--- Jump to the next/previous line in `lnums` (sorted) from the cursor.
---@param lnums integer[]
---@param dir 1|-1
local function jump(lnums, dir)
  local cur = fn.line(".")
  for i = dir > 0 and 1 or #lnums, dir > 0 and #lnums or 1, dir do
    if (lnums[i] - cur) * dir > 0 then
      return api.nvim_win_set_cursor(0, { lnums[i], 0 })
    end
  end
end

--- BufReadCmd for sessman://sessions
---@param buf integer
function M.read(buf)
  local sessman = require("sessman")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false
  M.render(buf)
  vim.bo[buf].filetype = "sessman"

  api.nvim_create_autocmd("BufEnter", {
    buffer = buf,
    callback = function()
      M.render(buf)
    end,
  })

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  --- Wrap an action on the session under the cursor, then refresh.
  local function act(f)
    return function()
      local s = state[buf] and state[buf].entries[fn.line(".")]
      if s then
        f(s)
        if api.nvim_buf_is_valid(buf) then
          M.render(buf)
        end
      end
    end
  end

  local function save(shada)
    return act(function(s)
      if s.unmanaged then
        if s.current then
          api.nvim_feedkeys(":SessionSave ", "n", false)
        end
      elseif s.current then
        sessman.save(nil, { shada = shada })
        if not api.nvim_buf_is_valid(buf) then
          M.open("") -- :mksession needed the window closed
        end
      elseif s.running then
        sessman.save_remote(s, { shada = shada })
        vim.defer_fn(function()
          if api.nvim_buf_is_valid(buf) then
            M.render(buf)
          end
        end, 300)
      end
    end)
  end

  map("<CR>", act(sessman.open), "Go to session")
  map("s", save(false), "Save session")
  map("S", save(true), "Save session with ShaDa")
  map("X", act(sessman.kill), "Kill session")
  map("D", act(sessman.delete), "Delete session")
  vim.keymap.set("n", "c<Space>", ":Session ", { buffer = buf, desc = "Populate :Session" })
  map(")", function()
    jump(vim.fn.sort(vim.tbl_keys(state[buf].entries), "n"), 1)
  end, "Next session")
  map("(", function()
    jump(vim.fn.sort(vim.tbl_keys(state[buf].entries), "n"), -1)
  end, "Previous session")
  map("]]", function()
    jump(state[buf].groups, 1)
  end, "Next group")
  map("[[", function()
    jump(state[buf].groups, -1)
  end, "Previous group")
  map("gq", function()
    vim.cmd(#api.nvim_tabpage_list_wins(0) > 1 and "close" or "bwipeout")
  end, "Close")
  map("g?", "<Cmd>help sessman-maps<CR>", "Help")

  api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      state[buf] = nil
    end,
  })
end

--- Like fugitive's :Git: without a position modifier, split at the edge of
--- the screen, spanning its full width (or height, with :vertical).
---@param mods string
---@return string
local function edge(mods)
  for word in mods:gmatch("%a+") do
    if vim.tbl_contains({ "aboveleft", "belowright", "leftabove", "rightbelow", "topleft", "botright", "tab" }, word) then
      return mods
    end
  end
  local after = vim.o.splitbelow
  if mods:find("vert") then
    after = vim.o.splitright
  end
  return (after and "botright " or "topleft ") .. mods
end

--- :Session without arguments: focus the buffer if it's visible, else open
--- it in a split at the top (honouring <mods>).
---@param mods string
function M.open(mods)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == M.name then
      local win = fn.bufwinid(buf)
      if vim.bo[buf].filetype ~= "sessman" then
        -- An empty stand-in, e.g. restored by a session file: replace it
        api.nvim_buf_delete(buf, { force = true })
      elseif win ~= -1 then
        api.nvim_set_current_win(win)
        return M.render(buf)
      end
    end
  end

  vim.cmd(edge(mods) .. " split " .. M.name)
end

return M
