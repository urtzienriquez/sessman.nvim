--- The :Session buffer, like fugitive's summary buffer.

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
    return out[1] or ""
  end
  out[#out + 1] = s.saved and ago(s.mtime or os.time()) or "unsaved"
  if s.running and s.cwd and s.cwd ~= s.project then
    local rel = s.project and vim.fs.relpath(s.project, s.cwd)
    out[#out + 1] = "in " .. (rel and (rel .. "/") or fn.fnamemodify(s.cwd, ":~"))
  end
  return table.concat(out, ", ")
end

local function pad(text, width)
  return text .. (" "):rep(width - fn.strdisplaywidth(text))
end

--- Running and Saved sections, one project:name line per session: the
--- project you are in first, "global" last.
---@param buf integer
function M.render(buf)
  local sessman = require("sessman")
  local here = sessman.here()

  local labels, rank = {}, {}
  local sections = { { title = "Running", list = {} }, { title = "Saved", list = {} } }
  for _, s in ipairs(sessman.list()) do
    local project = sessman.project_of(s)
    labels[s], rank[s] = sessman.display(s), project == here and 0 or project and 1 or 2
    table.insert(sections[s.running and 1 or 2].list, s)
  end

  local cur = sessman.current()
  local lines = {
    "Session: " .. (cur and cur.name or "(unnamed)"),
    "Project: " .. fn.fnamemodify(here, ":~"),
    "Help:    g?",
  }
  local st = { entries = {}, groups = {} }
  for _, section in ipairs(sections) do
    if #section.list > 0 then
      table.sort(section.list, function(a, b)
        if rank[a] ~= rank[b] then
          return rank[a] < rank[b]
        end
        return labels[a] < labels[b]
      end)
      lines[#lines + 1] = ""
      lines[#lines + 1] = ("%s (%d)"):format(section.title, #section.list)
      st.groups[#st.groups + 1] = #lines

      local width = 0
      for _, s in ipairs(section.list) do
        width = math.max(width, fn.strdisplaywidth(labels[s]))
      end
      for _, s in ipairs(section.list) do
        lines[#lines + 1] = (("  " .. pad(labels[s], width) .. "  " .. details(s)):gsub("%s+$", ""))
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

--- Move to the next (dir 1) or previous (-1) of the sorted `lnums`.
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

--- BufReadCmd for sessman://sessions and sessman://excluded.
---@param buf integer
function M.read(buf)
  if api.nvim_buf_get_name(buf) == "sessman://excluded" then
    -- Stands in for an excluded buffer (g:sessman_exclude): once the session
    -- is restored, its window goes away
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].buflisted = "nofile", "wipe", false
    vim.schedule(function()
      for _, win in ipairs(fn.win_findbuf(buf)) do
        if #api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win)) > 1 then
          pcall(api.nvim_win_close, win, true)
        else
          api.nvim_win_call(win, function()
            vim.cmd("enew")
          end)
        end
      end
      pcall(api.nvim_buf_delete, buf, { force = true })
    end)
    return
  end

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
  -- "Project:" follows the working directory
  api.nvim_create_autocmd("DirChanged", {
    callback = function()
      if not api.nvim_buf_is_valid(buf) then
        return true -- deletes this autocmd
      end
      if fn.bufwinid(buf) ~= -1 then
        M.render(buf)
      end
    end,
  })

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  --- An action on the entry under the cursor, then a refresh.
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
      local running = s.running and not s.unmanaged
      if running and s.saved and fn.confirm("Overwrite the saved session " .. s.name .. "?", "&Yes\n&No", 2) ~= 1 then
        return
      end
      if s.current and s.unmanaged then
        -- Fill in the command for the name: it teaches the command
        api.nvim_feedkeys(shada and ":Session save ++shada " or ":Session save ", "ni", false)
      elseif s.current then
        sessman.save(nil, { shada = shada })
        if not api.nvim_buf_is_valid(buf) then
          M.open("") -- save() closed it
        end
      elseif not running then
        local why = s.unmanaged and "not a session: go there (<CR>) and :Session save {name}"
          or (s.name .. " isn't running: go there (<CR>) to save it")
        api.nvim_echo({ { "sessman: " .. why } }, false, {})
      else
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
  local function kill(s)
    sessman.kill(s, false, true) -- reopen the list where we land
  end
  map("X", act(kill), "Kill session")
  map("D", act(sessman.delete), "Delete session")

  --- Visual mode: an action on all the selected entries, then a refresh.
  local function selected(f)
    return function()
      local from, to = fn.line("v"), fn.line(".")
      vim.cmd("normal! \27") -- leave visual mode
      local entries = {}
      for l = math.min(from, to), math.max(from, to) do
        entries[#entries + 1] = state[buf].entries[l]
      end
      if #entries > 0 then
        f(entries)
        if api.nvim_buf_is_valid(buf) then
          M.render(buf)
        end
      end
    end
  end
  vim.keymap.set("x", "X", selected(kill), { buffer = buf, desc = "Kill the selected sessions" })
  vim.keymap.set("x", "D", selected(sessman.delete), { buffer = buf, desc = "Delete the selected sessions" })
  vim.keymap.set("n", "co<Space>", ":Session switch ", { buffer = buf, desc = "Populate :Session switch" })
  vim.keymap.set("n", "cn<Space>", ":Session new ", { buffer = buf, desc = "Populate :Session new" })
  vim.keymap.set("n", "cs<Space>", ":Session save ", { buffer = buf, desc = "Populate :Session save" })
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

--- Without a position modifier, split at the screen's edge, like :Git.
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

--- Focus the list if visible, else open it (honouring <mods>).
---@param mods string
function M.open(mods)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf) == M.name then
      local win = fn.bufwinid(buf)
      if vim.bo[buf].filetype ~= "sessman" then
        -- An empty stand-in restored by an old session file
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
