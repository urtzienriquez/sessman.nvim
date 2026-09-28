--- Named sessions, either running (an Nvim server you :connect to) or saved
--- (a :mksession file), anchored to a project directory.
--- The server half is adapted from servery.nvim (MIT, (c) servery.nvim authors).

local M = {}

local api, fn, fs, uv = vim.api, vim.fn, vim.fs, vim.uv

---@class sessman.Session
---@field project string|false Directory, false for global sessions
---@field name string
---@field file string
---@field shada string
---@field sock string
---@field saved? boolean
---@field running? boolean
---@field current? boolean
---@field mtime? integer
---@field cwd? string
---@field active? integer When a UI last left it
---@field unmanaged? boolean A plain nvim, not a session
---@field pid? integer

local function err(msg)
  api.nvim_echo({ { "sessman: " .. msg, "ErrorMsg" } }, true, {})
end

local function yes(question)
  return fn.confirm(question, "&Yes\n&No", 2) == 1
end

local function valid(name)
  return name:match("^[^/:%s]+$") ~= nil
end

local function dir()
  return fs.normalize(vim.g.sessman_dir or (fn.stdpath("data") .. "/session"))
end

local function rundir()
  return fs.joinpath(fn.stdpath("run") --[[@as string]], "sessman")
end

local function abspath(path)
  return fs.normalize(fn.fnamemodify(fn.expand(path), ":p"))
end

--- The git root of a directory, else the directory.
local function root(path)
  return fs.root(path, ".git") or path
end

-- Session directories: the project path with "/" -> "%", or "global"
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
  return {
    project = project,
    name = name,
    file = base .. ".vim",
    shada = base .. ".shada",
    -- Short: socket paths are length limited
    sock = fs.joinpath(rundir(), fn.sha256((project or "") .. "\0" .. name):sub(1, 12)),
  }
end

---@return sessman.Session? nil in a plain nvim
function M.current()
  local id = vim.g.sessman_session
  return id and M.session(id.project, id.name) or nil
end

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

--- Plain nvim instances, one per pid.
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
        sock = addr,
        running = true,
        current = current and not vim.g.sessman_session or nil,
      }
    end
  end
  return out
end

--- Saved sessions (session dir), running ones (status files beside their
--- sockets) and plain nvims. Never blocks on a busy server.
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

  for dirname, type in fs.dir(dir()) do
    local project = type == "directory" and decode(dirname)
    if project ~= nil then
      for file, ftype in fs.dir(fs.joinpath(dir(), dirname)) do
        if ftype == "file" and file:sub(-4) == ".vim" then
          local s = get(project, file:sub(1, -5))
          local stat = uv.fs_stat(s.file)
          s.saved, s.mtime = true, stat and stat.mtime.sec
        end
      end
    end
  end

  local pids = {}
  for file in fs.dir(rundir()) do
    if file:sub(-5) == ".json" then
      local path = fs.joinpath(rundir(), file)
      local sock = path:sub(1, -6)
      local ok, st = pcall(vim.json.decode, table.concat(fn.readfile(path)))
      if ok and type(st) == "table" and st.name and alive(sock) then
        local s = get(st.project, st.name)
        s.running, s.cwd, s.active, s.pid = true, st.cwd, st.active, st.pid
        pids[st.pid] = true
      else -- stale
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
    -- Not on disk yet, e.g. while being adopted
    local s = get(cur.project, cur.name)
    s.current, s.running = true, true
  end
  return vim.list_extend(out, unmanaged(pids))
end

--- The project you are in.
---@return string
function M.here()
  return root(fs.normalize(fn.getcwd()))
end

--- The project an entry is listed under (a plain nvim's is its directory's).
---@return string|false
function M.project_of(s)
  if not s.unmanaged then
    return s.project
  end
  return s.name:sub(1, 1) == "/" and root(s.name) or s.name
end

--- ~/full/path:name, as the list and the picker show it.
---@return string
function M.display(s)
  local project = M.project_of(s)
  return (project and fn.fnamemodify(project, ":~") or "global") .. ":" .. (s.unmanaged and "(unnamed)" or s.name)
end

--- "global", the directory name, or ~/path when directory names clash.
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

--- The shortest :Session target for s: its name in the project you are in,
--- else project:name.
function M.label(s, here, sessions)
  return s.project == here and s.name or (project_label(s.project, sessions) .. ":" .. s.name)
end

--- Resolve "name" or "project:name" to a session, possibly a new one.
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

  -- A directory name: a project that has sessions, else a relative path
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

local function filter(items, arglead)
  return arglead == "" and items or fn.matchfuzzy(items, arglead)
end

---@param arglead string
---@param cmdline? string
---@return string[]
function M.complete(arglead, cmdline)
  -- Arguments after :Session or :S (modifiers are lowercase)
  local args = (cmdline or ""):match("%f[%w]S%w*!?%s+(.*)$") or ""
  local words = vim.tbl_filter(function(w)
    return w ~= "++shada"
  end, vim.split(args, "%s+", { trimempty = true }))
  local position = #words + (arglead == "" and 1 or 0)
  if position <= 1 then
    return filter(subcommands, arglead)
  elseif position > 2 then
    return {}
  elseif words[1] == "new" then
    return fn.getcompletion(arglead, "dir")
  end

  -- Only what the subcommand can act on
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

--- :Session and :S
function M.command(o)
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
    elseif not (s.running or s.saved) then
      err("no session " .. t)
      s = nil
    end
    return s
  end

  if sub == "switch" then
    return M.switch(target)
  elseif sub == "new" then
    return need_target() and M.new(target)
  elseif sub == "save" then
    return M.save(target, { bang = o.bang, shada = shada })
  elseif sub == "kill" then
    local s
    if target then
      s = find(target)
    else
      s = vim.iter(M.list()):find(function(x)
        return x.current
      end)
    end
    return s and M.kill(s)
  elseif sub == "delete" then
    local s = need_target() and find(target)
    return s and M.delete(s)
  end
  err(("unknown subcommand '%s' (%s)"):format(sub, table.concat(subcommands, ", ")))
end

--- The running session left most recently, other than this one.
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

--- Whether this plain nvim loses nothing if stopped when we leave it: no
--- unsaved changes, no running terminal (except `ignore`d ones, a picker's).
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

--- Remove sessman's buffers: they'd stay behind in the server we leave, and
--- :mksession would record them. A tab's last window gets another buffer.
local function close_windows()
  local function ours(buf)
    local name = api.nvim_buf_get_name(buf)
    return name == "sessman://sessions" or name == "sessman://excluded"
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

--- Move this UI to another server (:connect! stops the one we leave).
--- Replaced in tests.
function M.connect(addr, stop)
  close_windows()
  vim.cmd.connect({ args = { addr }, bang = stop })
end

---@return boolean ok
local function spawn(s)
  fn.mkdir(rundir(), "p")
  os.remove(s.sock) -- stale, if any

  local ident = ("lua vim.g.sessman_session={project=%s,name=%q}"):format(
    s.project and ("%q"):format(s.project) or "false",
    s.name
  )
  -- Session files size windows relative to the screen: use the UI's size,
  -- not the headless 80x24
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

  -- Ready once attach() wrote the status file, after sourcing the session
  local job = fn.jobstart(cmd, { detach = true, cwd = cwd, stdin = "null" })
  if job <= 0 or not vim.wait(5000, function()
    return uv.fs_stat(s.sock .. ".json") ~= nil
  end, 10) then
    err("failed to start " .. s.name)
    return false
  end
  return true
end

--- Go to s: jump if running, restore if saved, create otherwise.
---@param opts? { ignore?: table<integer, true> } See disposable()
function M.open(s, opts)
  local ignore = opts and opts.ignore
  if s.current then
    return
  elseif not s.unmanaged and not valid(s.name) then
    return err("invalid session name: " .. s.name)
  end
  if s.running or spawn(s) then
    M.connect(s.sock, disposable(ignore))
  end
end

--- vim.ui.select a session or plain nvim and go there, most recent first.
---@param running? boolean true: the running ones but this one; false: the others
local function pick(running)
  local items = vim.tbl_filter(function(s)
    if running == nil then
      return true
    end
    return running and (s.running and not s.current) or (not running and not s.running)
  end, M.list())
  if #items == 0 then
    local what = running == nil and "session" or running and "other running session" or "saved session not running"
    return err("no " .. what)
  end

  -- Running sessions by when they were left (the first is `switch -`'s),
  -- plain nvims, saved ones by last save; this one last
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

  -- A picker's own terminal (fzf-lua) is still running when it calls back:
  -- it mustn't keep this nvim alive
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
    vim.schedule(function() -- after the picker closed
      M.open(s, { ignore = ignore })
    end)
  end)
end

--- Go to a running or saved session ("-": the previous one). Without a
--- target, pick one; { running = true/false } narrows the picker.
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
  elseif not (s.running or s.saved) then
    return err(("no session %s; to create it: :Session new %s"):format(target, target))
  end
  M.open(s)
end

--- Create a session and go there.
function M.new(target)
  local s, msg = M.resolve(target, M.list())
  if not s then
    return err(msg)
  elseif s.running or s.saved then
    return err(("%s exists; to go there: :Session switch %s"):format(target, target))
  end
  M.open(s)
end

--- In a session's server: listen on its socket and keep its status file.
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
      f:write(vim.json.encode({ project = s.project, name = s.name, cwd = fn.getcwd(), pid = fn.getpid(), active = active }))
      f:close()
    end
  end
  write()

  -- A plain nvim made a session exits with its terminal unless its UIs are
  -- detachable (Nvim 0.13+); spawned servers survive anyway
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

--- Buffers matching g:sessman_exclude (autocmd-style patterns, on the name's
--- tail, or the full name if the pattern has a "/").
local function excluded()
  local out, patterns = {}, {}
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

--- :mksession without the excluded buffers: no :badd, and their windows show
--- "sessman://excluded", which closes itself on restore (buffer.lua).
local function mksession(file)
  local skip = excluded()
  local placeholder, swapped, restore = nil, {}, {}
  if next(skip) then
    placeholder = api.nvim_create_buf(false, false)
    api.nvim_buf_set_name(placeholder, "sessman://excluded")
    for buf in pairs(skip) do
      restore[buf] = { listed = vim.bo[buf].buflisted, hidden = vim.bo[buf].bufhidden }
      vim.bo[buf].buflisted, vim.bo[buf].bufhidden = false, "hide"
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

--- Save the current session; in a plain nvim, `name` makes it a session.
---@param name? string
---@param opts? { bang?: boolean, shada?: boolean }
function M.save(name, opts)
  opts = opts or {}
  local s = M.current()

  if s and name and name ~= s.name then
    -- It may still be this session's name, written as project:name
    local target = M.resolve(name, M.list())
    if not (target and target.project == s.project and target.name == s.name) then
      return err("this is session " .. s.name .. "; session names can't change")
    end
  elseif not s then
    if not name then
      return err("argument required: a name for this session")
    end
    local target, msg = M.resolve(name, M.list())
    if not target then
      return err(msg)
    elseif not valid(target.name) then
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

  -- Asked for, or already the session's: keep its ShaDa up to date
  local shada = opts.shada
    or (vim.o.shadafile ~= "" and abspath(vim.o.shadafile) == s.shada)
    or uv.fs_stat(s.shada) ~= nil
  if shada then
    vim.cmd("wshada! " .. fn.fnameescape(s.shada))
    vim.o.shadafile = s.shada
  end
  api.nvim_echo({ { "Saved session " .. s.name .. (shada and " with its ShaDa" or "") } }, false, {})
end

--- Run Lua in another server: scheduled there, or with `wait`, evaluated and
--- its result returned. False if the server can't be reached.
local function remote(addr, code, wait)
  local ok, chan = pcall(fn.sockconnect, "pipe", addr, { rpc = true })
  if not ok or chan <= 0 then
    return false
  end
  local _, result =
    pcall(vim.rpcrequest, chan, "nvim_exec_lua", wait and code or ("vim.schedule(function() " .. code .. " end)"), {})
  fn.chanclose(chan)
  return not wait or result
end

local UNSAVED = "return vim.iter(vim.api.nvim_list_bufs()):any(function(b) return vim.bo[b].modified end)"

--- Ask another running session to save itself.
---@param opts? { shada?: boolean }
function M.save_remote(s, opts)
  remote(s.sock, ("require('sessman').save(nil, { shada = %s })"):format(opts and opts.shada and "true" or "false"))
end

--- Stop a running session; its files stay. Stopping this one moves the UI to
--- the previous session (opening the list there if `list`), or quits.
---@param force? boolean Don't ask
---@param list? boolean
function M.kill(s, force, list)
  if not s.running then
    return
  end
  if not force then
    local unsaved
    if s.current then
      unsaved = load(UNSAVED)()
    else
      unsaved = remote(s.sock, UNSAVED, true) == true
    end
    if not yes(unsaved and (s.name .. " has unsaved changes. Kill anyway?") or ("Kill " .. s.name .. "?")) then
      return
    end
  end
  if s.current then
    local prev = M.previous()
    if prev then
      if list then
        remote(prev.sock, "require('sessman.buffer').open('')")
      end
      M.connect(prev.sock, false)
    end
    vim.cmd("qall!")
  elseif remote(s.sock, "vim.cmd('qall!')") then
    vim.wait(2000, function()
      return not uv.fs_stat(s.sock)
    end, 10)
  end
end

--- Remove a session's files, stopping it if it runs.
function M.delete(s)
  if s.unmanaged then
    return err("not a session: nothing to delete")
  elseif not yes("Delete session " .. s.name .. "?") then
    return
  end
  -- It writes its ShaDa when it quits: point it back to the global one, or
  -- the deleted file comes back
  if s.current then
    vim.o.shadafile = ""
  elseif s.running then
    remote(s.sock, "vim.o.shadafile = ''")
  end
  os.remove(s.file)
  os.remove(s.shada)
  fn.delete(fs.dirname(s.file), "d") -- only if empty
  M.kill(s, true)
end

return M
