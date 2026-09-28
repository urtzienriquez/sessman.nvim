--- sessman.nvim: named sessions that are either running (an Nvim server you
--- :connect to) or saved (a :mksession file), anchored to a project directory.
---
--- The server half (spawn a headless server, wait for its socket, :connect)
--- is adapted from servery.nvim (https://github.com/wurli/servery.nvim, MIT,
--- (c) servery.nvim authors).

local M = {}

local api, fn, fs, uv = vim.api, vim.fn, vim.fs, vim.uv

---@class sessman.Session
---@field project string|false Anchor directory, false for global sessions
---@field name string
---@field file string Saved session file
---@field shada string Per-session ShaDa file (optional)
---@field sock string Socket the server listens on while running
---@field saved? boolean
---@field running? boolean
---@field current? boolean
---@field mtime? integer
---@field cwd? string
---@field active? integer Last time a UI left it (os.time())
---@field unmanaged? boolean A plain nvim that is not a sessman session
---@field pid? integer

local function err(msg)
  api.nvim_echo({ { "sessman: " .. msg, "ErrorMsg" } }, true, {})
end

---@return string
local function dir()
  return fs.normalize(vim.g.sessman_dir or (fn.stdpath("data") .. "/session"))
end

---@return string
local function rundir()
  return fs.joinpath(fn.stdpath("run") --[[@as string]], "sessman")
end

---@param path string
---@return string
local function abspath(path)
  return fs.normalize(fn.fnamemodify(fn.expand(path), ":p"))
end

--- Session directories are named after the project path with "/" -> "%".
local function encode(project)
  return project and (project:gsub("/", "%%")) or "global"
end

local function decode(dirname)
  if dirname == "global" then
    return false
  elseif dirname:sub(1, 1) == "%" then
    return (dirname:gsub("%%", "/"))
  end
end

---@param project string|false
---@param name string
---@return sessman.Session
function M.session(project, name)
  local base = fs.joinpath(dir(), encode(project), name)
  local id = fn.sha256((project or "") .. "\0" .. name):sub(1, 12)
  return {
    project = project,
    name = name,
    file = base .. ".vim",
    shada = base .. ".shada",
    sock = fs.joinpath(rundir(), id),
  }
end

--- The session this instance is, or nil for a plain nvim.
---@return sessman.Session?
function M.current()
  local id = vim.g.sessman_session
  return id and M.session(id.project, id.name) or nil
end

---@param addr string
local function alive(addr)
  if vim.tbl_contains(fn.serverlist(), addr) then
    return true
  end
  local ok, chan = pcall(fn.sockconnect, "pipe", addr)
  if ok and chan > 0 then
    fn.chanclose(chan)
    return true
  end
  return false
end

--- Plain nvim instances (not sessman sessions), deduplicated by pid.
---@param managed_pids table<integer, true>
---@return sessman.Session[]
local function unmanaged(managed_pids)
  local ok, addrs = pcall(fn.serverlist, { peer = true })
  if not ok then
    return {}
  end
  local own = fn.serverlist()
  local out, seen = {}, {}
  for _, addr in ipairs(addrs) do
    local pid = tonumber(fs.basename(addr):match("^nvim%.(%d+)%.%d+$"))
    if pid and not seen[pid] and not managed_pids[pid] then
      seen[pid] = true
      local current = vim.tbl_contains(own, addr)
      out[#out + 1] = {
        unmanaged = true,
        name = current and fn.getcwd() or uv.fs_readlink("/proc/" .. pid .. "/cwd") or ("pid " .. pid),
        project = false,
        sock = addr,
        pid = pid,
        running = true,
        current = current and not vim.g.sessman_session or nil,
      }
    end
  end
  return out
end

--- Every known session: saved ones from the session directory, running ones
--- from the status files next to their sockets, and plain nvim instances.
--- Never blocks on a busy server.
---@return sessman.Session[]
function M.list()
  local by_key, out = {}, {}
  local function get(project, name)
    local key = (project or "") .. "\0" .. name
    if not by_key[key] then
      by_key[key] = M.session(project, name)
      out[#out + 1] = by_key[key]
    end
    return by_key[key]
  end

  local root = dir()
  for dirname, type in fs.dir(root) do
    local project = type == "directory" and decode(dirname)
    if project ~= nil then
      for file, ftype in fs.dir(fs.joinpath(root, dirname)) do
        if ftype == "file" and file:sub(-4) == ".vim" then
          local s = get(project, file:sub(1, -5))
          s.saved = true
          local stat = uv.fs_stat(s.file)
          s.mtime = stat and stat.mtime.sec
        end
      end
    end
  end

  local run, pids = rundir(), {}
  for file in fs.dir(run) do
    if file:sub(-5) == ".json" then
      local path = fs.joinpath(run, file)
      local ok, st = pcall(vim.json.decode, table.concat(fn.readfile(path)))
      local sock = path:sub(1, -6)
      if ok and type(st) == "table" and st.name and alive(sock) then
        local s = get(st.project, st.name)
        s.running, s.cwd, s.active, s.pid = true, st.cwd, st.active, st.pid
        pids[st.pid] = true
      else
        os.remove(path)
        os.remove(sock)
      end
    end
  end

  local cur = M.current()
  for _, s in ipairs(out) do
    s.current = cur and s.project == cur.project and s.name == cur.name or nil
  end
  if cur and not by_key[(cur.project or "") .. "\0" .. cur.name] then
    -- Current session not (yet) visible on disk, e.g. mid-adoption
    local s = get(cur.project, cur.name)
    s.current, s.running = true, true
  end
  return vim.list_extend(out, unmanaged(pids))
end

--- The project the user is "in": the git root, else the working directory.
---@return string
function M.here()
  local cwd = fs.normalize(fn.getcwd())
  return fs.normalize(fs.root(cwd, ".git") or cwd)
end

--- The project an entry is listed under: a session's own, or for a plain
--- nvim the git root of its working directory (or the directory itself).
---@param s sessman.Session
---@return string|false
function M.project_of(s)
  if not s.unmanaged then
    return s.project
  end
  local dir = s.name:sub(1, 1) == "/" and s.name
  return dir and fs.normalize(fs.root(dir, ".git") or dir) or s.name
end

--- How the list and the picker show an entry: ~/full/path:name
---@param s sessman.Session
---@return string
function M.display(s)
  local project = M.project_of(s)
  return (project and fn.fnamemodify(project, ":~") or "global") .. ":" .. (s.unmanaged and "(unnamed)" or s.name)
end

--- Short name of a project: "global", its directory name, or ~/path when
--- another project has the same directory name.
---@param project string|false
---@param sessions sessman.Session[]
---@return string
local function project_label(project, sessions)
  if not project then
    return "global"
  end
  local base = fs.basename(project)
  for _, o in ipairs(sessions) do
    if o.project and o.project ~= project and fs.basename(o.project) == base then
      base = nil
      break
    end
  end
  return (base and base ~= "global") and base or fn.fnamemodify(project, ":~")
end

--- How a session is referred to in :Session: bare name for the here project,
--- global:name, project-basename:name, or ~/path:name when ambiguous.
---@param s sessman.Session
---@param here string
---@param sessions sessman.Session[]
---@return string
function M.label(s, here, sessions)
  return s.project == here and s.name or (project_label(s.project, sessions) .. ":" .. s.name)
end

--- Resolve a :Session target, "name" or "project:name" (like fugitive's
--- "object:path"), to a session, possibly one that doesn't exist yet.
---@param target string
---@param sessions sessman.Session[]
---@return sessman.Session?
---@return string? error
function M.resolve(target, sessions)
  local proj, name = target:match("^(.*):([^:]+)$")
  local function find(project, n)
    for _, s in ipairs(sessions) do
      if not s.unmanaged and s.project == project and s.name == n then
        return s
      end
    end
  end

  if not proj then
    if target:find("/") then
      return nil, ("'%s': write {project}:{name}, e.g. ~/papers/thesis:writing"):format(target)
    end
    local here = M.here()
    return find(here, target) or find(false, target) or M.session(here, target)
  elseif proj == "" then
    return nil, "missing project before ':' (global sessions: global:" .. name .. ")"
  elseif proj == "global" then
    return find(false, name) or M.session(false, name)
  elseif proj:find("/") or proj:find("^~") or proj == "." or proj == ".." then
    local path = abspath(proj)
    if fn.isdirectory(path) == 0 then
      return nil, "not a directory: " .. path
    end
    return find(path, name) or M.session(path, name)
  end

  local matches = {}
  for _, s in ipairs(sessions) do
    if s.project and not s.unmanaged and fs.basename(s.project) == proj then
      matches[s.project] = true
    end
  end
  local projects = vim.tbl_keys(matches)
  if #projects > 1 then
    return nil, "ambiguous project '" .. proj .. "', use its path"
  elseif #projects == 1 then
    return find(projects[1], name) or M.session(projects[1], name)
  elseif fn.isdirectory(proj) == 1 then
    return find(abspath(proj), name) or M.session(abspath(proj), name)
  end
  return nil, "unknown project: " .. proj
end

local subcommands = { "switch", "new", "save", "kill", "delete" }

---@param items string[]
---@param arglead string
local function filter(items, arglead)
  return arglead == "" and items or fn.matchfuzzy(items, arglead)
end

--- :Session completion: subcommands, then sessions (fuzzy), or directories
--- for :Session new.
---@param arglead string
---@param cmdline? string
---@return string[]
function M.complete(arglead, cmdline)
  -- Arguments after the command name (:Session or :S; modifiers are lowercase)
  local args = (cmdline or ""):match("%f[%w]S%w*!?%s+(.*)$") or ""
  local words = vim.tbl_filter(function(w)
    return w ~= "++shada" -- an option, not a positional argument
  end, vim.split(args, "%s+", { trimempty = true }))
  local position = #words + (arglead == "" and 1 or 0)
  if position <= 1 then
    return filter(subcommands, arglead)
  elseif position > 2 then
    return {}
  elseif words[1] == "new" then
    return fn.getcompletion(arglead, "dir")
  end

  -- Only sessions the subcommand can act on
  local wanted = ({
    kill = function(s)
      return s.running
    end,
    delete = function(s)
      return s.saved
    end,
    save = function(s)
      return s.saved
    end,
  })[words[1]] or function()
    return true
  end

  local sessions = M.list()
  local here = M.here()
  local items = {}
  for _, s in ipairs(sessions) do
    if not s.unmanaged and wanted(s) then
      items[#items + 1] = M.label(s, here, sessions)
    end
  end
  table.sort(items)
  if words[1] == "save" and not args:find("++shada", 1, true) then
    table.insert(items, 1, "++shada")
  elseif words[1] == "switch" then
    table.insert(items, 1, "-")
  end
  return filter(items, arglead)
end

--- The :Session command.
---@param o table Arguments of nvim_create_user_command's callback
function M.command(o)
  -- ++shada (like :write ++enc): save with the session's own ShaDa
  local shada = false
  local args = vim.tbl_filter(function(a)
    shada = shada or a == "++shada"
    return a ~= "++shada"
  end, o.fargs)
  local sub, target = args[1], args[2]
  if not sub then
    return require("sessman.buffer").open(o.mods)
  elseif #args > 2 then
    return err("too many arguments")
  elseif shada and sub ~= "save" then
    return err("++shada only goes with save")
  end

  local function need_target()
    if not target then
      err(("argument required: :Session %s {session}"):format(sub))
    end
    return target
  end
  local function find(t)
    local s, msg = M.resolve(t, M.list())
    if not s then
      err(msg)
    elseif not (s.running or s.saved or s.unmanaged) then
      err("no session " .. t)
      s = nil
    end
    return s
  end

  if sub == "switch" then
    return M.switch(target) -- no target: pick one
  elseif sub == "new" then
    return need_target() and M.new(target)
  elseif sub == "save" then
    return M.save(target, { bang = o.bang, shada = shada })
  elseif sub == "kill" then
    if not target then
      for _, s in ipairs(M.list()) do
        if s.current then
          return M.kill(s)
        end
      end
      return
    end
    local s = find(target)
    return s and M.kill(s)
  elseif sub == "delete" then
    local s = need_target() and find(target)
    return s and M.delete(s)
  end
  err(("unknown subcommand '%s' (%s)"):format(sub, table.concat(subcommands, ", ")))
end

--- The running session left most recently, other than this one.
---@param sessions? sessman.Session[]
---@return sessman.Session?
function M.previous(sessions)
  local best
  for _, s in ipairs(sessions or M.list()) do
    if s.running and not s.current and not s.unmanaged and (not best or (s.active or 0) > (best.active or 0)) then
      best = s
    end
  end
  return best
end

--- A plain nvim that would lose nothing by stopping: no unsaved changes and
--- no terminal still running. It's stopped when we move away; sessions and
--- anything else keep running.
---@param ignore? table<integer, true> Terminal buffers not to count (a picker's)
local function disposable(ignore)
  if vim.g.sessman_session or #api.nvim_list_uis() > 1 then
    return false
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      return false
    end
    if
      vim.bo[buf].buftype == "terminal"
      and not (ignore and ignore[buf])
      and fn.jobwait({ vim.bo[buf].channel }, 0)[1] == -1
    then
      return false
    end
  end
  return true
end

--- Get rid of sessman's own buffers: they'd be left behind in the old server,
--- and :mksession would record them as empty buffers. A window that is the
--- last in its tab shows the alternate buffer (or a new one) instead.
local function close_windows()
  local function ours(buf)
    return api.nvim_buf_get_name(buf):match("^sessman://") ~= nil
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(win) and ours(api.nvim_win_get_buf(win)) then
      if #api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win)) > 1 then
        pcall(api.nvim_win_close, win, true)
      else
        api.nvim_win_call(win, function()
          local alt = fn.bufnr("#")
          vim.cmd(alt > 0 and fn.buflisted(alt) == 1 and not ours(alt) and ("buffer " .. alt) or "enew")
        end)
      end
    end
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if ours(buf) then
      pcall(api.nvim_buf_delete, buf, { force = true })
    end
  end
end

--- Move this UI to another server. Replaced in tests.
---@param addr string
---@param stop boolean Stop the server we leave (:connect!)
function M.connect(addr, stop)
  close_windows()
  vim.cmd.connect({ args = { addr }, bang = stop })
end

---@param s sessman.Session
---@return boolean ok
local function spawn(s)
  fn.mkdir(rundir(), "p")
  os.remove(s.sock) -- a stale one, if list() found it dead

  local ident = ("lua vim.g.sessman_session={project=%s,name=%q}"):format(
    s.project and ("%q"):format(s.project) or "false",
    s.name
  )
  -- Session files size windows relative to &columns/&lines: source them at
  -- the size of the UI that will attach, not the headless 80x24.
  local size = ("set columns=%d lines=%d"):format(vim.o.columns, vim.o.lines)
  local cmd = { vim.v.progpath, "--headless", "--listen", s.sock, "--cmd", ident, "--cmd", size }
  if s.saved then
    if uv.fs_stat(s.shada) then
      vim.list_extend(cmd, { "-i", s.shada })
    end
    vim.list_extend(cmd, { "-c", "source " .. fn.fnameescape(s.file) })
  end
  vim.list_extend(cmd, { "-c", "lua require('sessman').attach()" })

  local cwd = fn.getcwd()
  if s.project and not (cwd == s.project or vim.startswith(cwd, s.project .. "/")) then
    cwd = fn.isdirectory(s.project) == 1 and s.project or cwd
  end

  -- The status file is written by attach(), after the session is sourced
  local job = fn.jobstart(cmd, { detach = true, cwd = cwd, stdin = "null" })
  if job <= 0 or not vim.wait(5000, function()
    return uv.fs_stat(s.sock .. ".json") ~= nil
  end, 10) then
    err("failed to start " .. s.name)
    return false
  end
  return true
end

--- Go to a session: jump if running, restore if saved, create otherwise.
---@param s sessman.Session
---@param opts? { ignore?: table<integer, true> } Terminal buffers that don't keep this nvim alive
function M.open(s, opts)
  local ignore = opts and opts.ignore
  if s.current then
    return
  end
  if s.unmanaged then
    return M.connect(s.sock, disposable(ignore))
  end
  if not s.name:match("^[^/:%s]+$") then
    return err("invalid session name: " .. s.name)
  end
  if s.running or spawn(s) then
    M.connect(s.sock, disposable(ignore))
  end
end

--- Pick a session, or plain nvim, with vim.ui.select (and so any picker
--- that hooks it) and go there.
---@param running? boolean true: the running ones but this one; false: the not running ones
local function pick(running)
  local items = vim.tbl_filter(function(s)
    if running == nil then
      return true
    end
    return running and (s.running and not s.current) or (not running and not s.running)
  end, M.list())
  local what = running == nil and "session" or running and "other running session" or "saved session not running"
  if #items == 0 then
    return err("no " .. what)
  end

  -- Most recent first: running sessions by when they were left (the first is
  -- where `switch -` goes), plain nvims, saved ones by last save; this one last
  local function key(s)
    return {
      s.current and 1 or 0,
      s.unmanaged and 1 or s.running and 0 or 2,
      -((s.running and s.active) or s.mtime or 0),
      M.display(s),
    }
  end
  table.sort(items, function(a, b)
    local ka, kb = key(a), key(b)
    for i = 1, #ka do
      if ka[i] ~= kb[i] then
        return ka[i] < kb[i]
      end
    end
    return false
  end)

  -- Pickers like fzf-lua run in a terminal that is still alive when they
  -- call back: it must not count as "a running terminal worth keeping".
  local before = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    before[buf] = vim.bo[buf].buftype == "terminal" or nil
  end

  vim.ui.select(items, {
    prompt = running == nil and "Session " or running and "Running session " or "Saved session ",
    format_item = function(s)
      local label = M.display(s)
      return s.current and (label .. "  (current)") or s.running and (label .. "  (running)") or label
    end,
  }, function(s)
    if not s then
      return
    end
    local ignore = {}
    for _, buf in ipairs(api.nvim_list_bufs()) do
      ignore[buf] = vim.bo[buf].buftype == "terminal" and not before[buf] or nil
    end
    vim.schedule(function() -- let the picker close first
      M.open(s, { ignore = ignore })
    end)
  end)
end

--- :Session switch {target}: jump to a running session or restore a saved
--- one; "-" is the previous session. Without a target, pick one;
--- `switch({ running = true })` picks among the running ones.
---@param target? string|{ running?: boolean }
function M.switch(target)
  if type(target) ~= "string" then
    return pick(target and target.running)
  end
  local sessions = M.list()
  local s, msg
  if target == "-" then
    s, msg = M.previous(sessions), "no previous session"
  else
    s, msg = M.resolve(target, sessions)
  end
  if not s then
    return err(msg)
  elseif not (s.running or s.saved or s.unmanaged) then
    return err(("no session %s; to create it: :Session new %s"):format(target, target))
  end
  M.open(s)
end

--- :Session new {target}: create a fresh session and switch to it.
---@param target string
function M.new(target)
  local s, msg = M.resolve(target, M.list())
  if not s then
    return err(msg)
  elseif s.running or s.saved then
    return err(("%s exists; to go there: :Session switch %s"):format(target, target))
  end
  M.open(s)
end

--- Run inside a session's server: listen on its socket and keep its status
--- file up to date. Called by spawned servers and when adopting.
function M.attach()
  local s = M.current()
  if not s then
    return
  end
  fn.mkdir(rundir(), "p")
  if not vim.tbl_contains(fn.serverlist(), s.sock) then
    fn.serverstart(s.sock)
  end

  local status, active = s.sock .. ".json", os.time()
  local function write()
    local f = io.open(status, "w")
    if f then
      f:write(vim.json.encode({
        project = s.project,
        name = s.name,
        cwd = fn.getcwd(),
        pid = fn.getpid(),
        active = active,
      }))
      f:close()
    end
  end
  write()

  -- An adopted session is a plain nvim, which exits with its terminal unless
  -- its UIs are detachable (:detach!, Nvim 0.13+). Spawned headless servers
  -- survive anyway.
  local function detachable()
    if #api.nvim_list_uis() > 0 then
      pcall(vim.cmd, "silent detach!")
    end
  end
  detachable()

  local group = api.nvim_create_augroup("sessman_session", { clear = true })
  api.nvim_create_autocmd({ "UIEnter", "UILeave" }, {
    group = group,
    callback = function(ev)
      active = os.time()
      write()
      if ev.event == "UIEnter" then
        detachable()
      end
    end,
  })
  api.nvim_create_autocmd("DirChanged", { group = group, callback = write })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      os.remove(status)
    end,
  })
end

--- Buffers matching g:sessman_exclude: autocmd-style patterns, matched
--- against the name's tail, or the full name when the pattern has a "/".
---@return table<integer, true>
local function excluded()
  local out = {}
  local patterns = {}
  for _, p in ipairs(vim.g.sessman_exclude or {}) do
    patterns[#patterns + 1] = { full = p:find("/") ~= nil, re = fn.glob2regpat(p) }
  end
  if #patterns == 0 then
    return out
  end
  for _, buf in ipairs(api.nvim_list_bufs()) do
    local name = api.nvim_buf_get_name(buf)
    for _, p in ipairs(patterns) do
      if name ~= "" and fn.match(p.full and name or fs.basename(name), p.re) ~= -1 then
        out[buf] = true
        break
      end
    end
  end
  return out
end

--- :mksession without the excluded buffers: they get no :badd, and their
--- windows are recorded showing "sessman://excluded", which closes itself
--- when the session is restored (see buffer.lua).
---@param file string
local function mksession(file)
  local skip = excluded()
  local placeholder, swapped, restore = nil, {}, {}
  if next(skip) then
    placeholder = api.nvim_create_buf(false, false)
    api.nvim_buf_set_name(placeholder, "sessman://excluded")
    for buf in pairs(skip) do
      restore[buf] = { listed = vim.bo[buf].buflisted, hidden = vim.bo[buf].bufhidden }
      vim.bo[buf].buflisted = false
      vim.bo[buf].bufhidden = "hide" -- survive leaving its windows
    end
    for _, win in ipairs(api.nvim_list_wins()) do
      local buf = api.nvim_win_get_buf(win)
      if skip[buf] then
        swapped[win] = buf
        api.nvim_win_set_buf(win, placeholder)
      end
    end
  end

  local ok, e = pcall(vim.cmd, "mksession! " .. fn.fnameescape(file))

  for win, buf in pairs(swapped) do
    if api.nvim_win_is_valid(win) then
      api.nvim_win_set_buf(win, buf)
    end
  end
  for buf, o in pairs(restore) do
    if api.nvim_buf_is_valid(buf) then
      vim.bo[buf].buflisted, vim.bo[buf].bufhidden = o.listed, o.hidden
    end
  end
  if placeholder then
    pcall(api.nvim_buf_delete, placeholder, { force = true })
  end
  if not ok then
    error(e, 0)
  end
end

--- :Session save[!] [name]
---@param name? string Name for a plain nvim (adopts it as a session)
---@param opts? { bang?: boolean, shada?: boolean }
function M.save(name, opts)
  opts = opts or {}
  local s = M.current()

  if s and name and name ~= s.name then
    return err("this is session " .. s.name .. "; session names can't change")
  elseif not s then
    if not name then
      return err("argument required: a name for this session")
    end
    local sessions = M.list()
    local target, msg = M.resolve(name, sessions)
    if not target then
      return err(msg)
    elseif not target.name:match("^[^/:%s]+$") then
      return err("invalid session name: " .. target.name)
    elseif target.running then
      return err(target.name .. " is running; kill it first")
    elseif target.saved and not opts.bang then
      return err(target.name .. " exists (add ! to override)")
    end
    s = target
    vim.g.sessman_session = { project = s.project, name = s.name }
    M.attach()
  end

  close_windows()
  fn.mkdir(fs.dirname(s.file), "p")
  mksession(s.file)

  local shada_on = vim.o.shadafile ~= "" and abspath(vim.o.shadafile) == s.shada
  local shada = opts.shada or shada_on or uv.fs_stat(s.shada) ~= nil
  if shada then
    vim.cmd("wshada! " .. fn.fnameescape(s.shada))
    vim.o.shadafile = s.shada
  end
  api.nvim_echo({ { "Saved session " .. s.name .. (shada and " with its ShaDa" or "") } }, false, {})
end

--- Run a Lua chunk in another server without waiting for it to finish.
---@param addr string
---@param code string
local function remote(addr, code)
  local ok, chan = pcall(fn.sockconnect, "pipe", addr, { rpc = true })
  if not ok or chan <= 0 then
    return false
  end
  pcall(vim.rpcrequest, chan, "nvim_exec_lua", "vim.schedule(function() " .. code .. " end)", {})
  fn.chanclose(chan)
  return true
end

--- Ask a running session to save itself.
---@param s sessman.Session
---@param opts? { shada?: boolean }
function M.save_remote(s, opts)
  remote(s.sock, ("require('sessman').save(nil, { shada = %s })"):format(opts and opts.shada and "true" or "false"))
end

--- Stop a running session (its saved files are kept). Killing the current
--- session moves this UI to the previous one, or quits.
---@param s sessman.Session
---@param force? boolean Skip the confirmation
---@param list? boolean Killing the current session: open the list where we land
function M.kill(s, force, list)
  if not s.running then
    return
  end
  if s.current then
    local unsaved = vim.iter(api.nvim_list_bufs()):any(function(buf)
      return vim.bo[buf].modified
    end)
    local msg = unsaved and "Session has unsaved changes. Kill anyway?" or ("Kill " .. s.name .. "?")
    if not force and fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then
      return
    end
    local prev = M.previous()
    if prev then
      if list then
        remote(prev.sock, "require('sessman.buffer').open('')")
      end
      M.connect(prev.sock, false)
    end
    vim.cmd("qall!")
    return
  end
  if not force and fn.confirm("Kill " .. s.name .. "?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  if remote(s.sock, "vim.cmd('qall!')") then
    vim.wait(2000, function()
      return not uv.fs_stat(s.sock)
    end, 10)
  end
end

--- Delete a session's files, killing it first if it runs.
---@param s sessman.Session
function M.delete(s)
  if s.unmanaged or fn.confirm("Delete session " .. s.name .. "?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  os.remove(s.file)
  os.remove(s.shada)
  fn.delete(fs.dirname(s.file), "d") -- only if empty
  M.kill(s, true)
end

return M
