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
function M.dir()
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
function M.new(project, name)
  local base = fs.joinpath(M.dir(), encode(project), name)
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
  return id and M.new(id.project, id.name) or nil
end

---@param a sessman.Session?
---@param b sessman.Session?
local function same(a, b)
  return a ~= nil and b ~= nil and a.project == b.project and a.name == b.name
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

local function readfile(path)
  local f = io.open(path, "r")
  if not f then
    return
  end
  local data = f:read("*a")
  f:close()
  return data
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
      by_key[key] = M.new(project, name)
      out[#out + 1] = by_key[key]
    end
    return by_key[key]
  end

  local root = M.dir()
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
      local ok, st = pcall(vim.json.decode, readfile(path) or "")
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
    s.current = same(s, cur) or nil
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

--- Short name of a project: "global", its directory name, or ~/path when
--- another project has the same directory name.
---@param project string|false
---@param sessions sessman.Session[]
---@return string
function M.project_label(project, sessions)
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
--- global/name, project-basename/name, or ~/path/name when ambiguous.
---@param s sessman.Session
---@param here string
---@param sessions sessman.Session[]
---@return string
function M.label(s, here, sessions)
  if s.unmanaged then
    return fn.fnamemodify(s.name, ":~")
  elseif s.project == here then
    return s.name
  end
  return M.project_label(s.project, sessions) .. "/" .. s.name
end

--- Resolve a :Session target to a session (possibly one that doesn't exist yet).
---@param target string
---@param sessions sessman.Session[]
---@return sessman.Session?
---@return string? error
function M.resolve(target, sessions)
  local proj, name = target:match("^(.*)/([^/]+)$")
  local function find(project, n)
    for _, s in ipairs(sessions) do
      if not s.unmanaged and s.project == project and s.name == n then
        return s
      end
    end
  end

  if not proj then
    local here = M.here()
    return find(here, target) or find(false, target) or M.new(here, target)
  elseif proj == "global" then
    return find(false, name) or M.new(false, name)
  elseif proj == "" or proj:find("[/~.]") then
    local path = abspath(proj == "" and "/" or proj)
    if fn.isdirectory(path) == 0 then
      return nil, "not a directory: " .. path
    end
    return find(path, name) or M.new(path, name)
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
    return find(projects[1], name) or M.new(projects[1], name)
  elseif fn.isdirectory(proj) == 1 then
    return find(abspath(proj), name) or M.new(abspath(proj), name)
  end
  return nil, "unknown project: " .. proj
end

--- :Session completion (fuzzy).
---@param arglead string
---@return string[]
function M.complete(arglead)
  local sessions = M.list()
  local here = M.here()
  local items = {}
  for _, s in ipairs(sessions) do
    if not s.unmanaged then
      items[#items + 1] = M.label(s, here, sessions)
    end
  end
  table.sort(items)
  return arglead == "" and items or fn.matchfuzzy(items, arglead)
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
  if uv.fs_stat(s.sock) then
    os.remove(s.sock) -- stale: list() found it dead
  end

  local ident = ("lua vim.g.sessman_session={project=%s,name=%q}"):format(
    s.project and ("%q"):format(s.project) or "false",
    s.name
  )
  -- Session files size windows relative to &columns/&lines: source them at
  -- the size of the UI that will attach, not the headless 80x24.
  local size = ("set columns=%d lines=%d"):format(vim.o.columns, vim.o.lines)
  local cmd = { vim.v.progpath, "--headless", "--listen", s.sock, "--cmd", ident, "--cmd", size }
  if s.saved and uv.fs_stat(s.shada) then
    vim.list_extend(cmd, { "-i", s.shada })
  end
  if s.saved then
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
  if not s.name:match("^[^/%s]+$") then
    return err("invalid session name: " .. s.name)
  end
  if s.running or spawn(s) then
    M.connect(s.sock, disposable(ignore))
  end
end

--- :Session {target}
---@param target string
function M.go(target)
  local sessions = M.list()
  local s, msg
  if target == "-" then
    s, msg = M.previous(sessions), "no previous session"
  else
    s, msg = M.resolve(target, sessions)
  end
  if not s then
    return err(msg)
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

--- :SessionSave[!] [name]
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
    elseif not target.name:match("^[^/%s]+$") then
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
  vim.cmd("mksession! " .. fn.fnameescape(s.file))

  local shada_on = vim.o.shadafile ~= "" and abspath(vim.o.shadafile) == s.shada
  if opts.shada or shada_on or uv.fs_stat(s.shada) then
    vim.cmd("wshada! " .. fn.fnameescape(s.shada))
    vim.o.shadafile = s.shada
  end
  api.nvim_echo({ { "Saved session " .. s.name } }, false, {})
end

local function modified()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].modified then
      return true
    end
  end
  return false
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
  if s.current then
    return M.save(nil, opts)
  end
  remote(s.sock, ("require('sessman').save(nil, { shada = %s })"):format(opts and opts.shada and "true" or "false"))
end

--- Stop a running session (its saved files are kept). Killing the current
--- session moves this UI to the previous one, or quits.
---@param s sessman.Session
---@param force? boolean Skip the confirmation
function M.kill(s, force)
  if not s.running then
    return
  end
  if s.current then
    local msg = modified() and "Session has unsaved changes. Kill anyway?" or ("Kill " .. s.name .. "?")
    if not force and fn.confirm(msg, "&Yes\n&No", 2) ~= 1 then
      return
    end
    local prev = M.previous()
    if prev then
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

--- Pick a session with vim.ui.select (and so with any picker that hooks it).
function M.pick()
  local sessions = M.list()
  local here = M.here()
  local items = vim.tbl_filter(function(s)
    return not s.unmanaged
  end, sessions)

  -- Pickers like fzf-lua run in a terminal that is still alive when they
  -- call back: it must not count as "a running terminal worth keeping".
  local before = {}
  for _, buf in ipairs(api.nvim_list_bufs()) do
    before[buf] = vim.bo[buf].buftype == "terminal" or nil
  end
  local function picker_terminals()
    local out = {}
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if vim.bo[buf].buftype == "terminal" and not before[buf] then
        out[buf] = true
      end
    end
    return out
  end

  vim.ui.select(items, {
    prompt = "Session ",
    format_item = function(s)
      local label = M.label(s, here, sessions)
      return s.current and (label .. "  (current)") or s.running and (label .. "  (running)") or label
    end,
  }, function(s)
    if s then
      local ignore = picker_terminals()
      vim.schedule(function() -- let the picker close first
        M.open(s, { ignore = ignore })
      end)
    end
  end)
end

--- Compatibility with the old setup() call; configuration is vim.g.sessman_dir.
---@param opts? { session_dir?: string }
function M.setup(opts)
  if opts and opts.session_dir then
    vim.g.sessman_dir = opts.session_dir
  end
end

return M
