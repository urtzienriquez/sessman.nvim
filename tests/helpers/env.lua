-- Per-test sandbox: temp session dir, runtime dir (sockets + status files),
-- config dir for spawned servers, and a project dir.
local M = {}

local root_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

local originals = {
  run = vim.env.XDG_RUNTIME_DIR,
  config = vim.env.XDG_CONFIG_HOME,
  data = vim.env.XDG_DATA_HOME,
  state = vim.env.XDG_STATE_HOME,
  echo = vim.api.nvim_echo,
  confirm = vim.fn.confirm,
}

--- Resolve symlinks (e.g. /tmp on some systems) so paths compare equal to
--- what getcwd() returns.
local function realpath(p)
  return vim.uv.fs_realpath(p) or p
end

function M.fresh(mod)
  package.loaded[mod] = nil
  return require(mod)
end

function M.setup()
  M.root = realpath(vim.fn.tempname())
  vim.fn.mkdir(M.root, "p")
  M.root = realpath(M.root)
  M.project = M.root .. "/project"
  vim.fn.mkdir(M.project .. "/sub", "p")
  vim.g.sessman_dir = M.root .. "/sessions"
  vim.g.sessman_session = nil

  -- Short runtime dir: socket paths are length limited
  M.run = realpath(vim.fn.tempname())
  vim.fn.mkdir(M.run, "p")
  vim.env.XDG_RUNTIME_DIR = M.run

  -- Spawned servers inherit these: nothing may touch the real XDG dirs.
  -- Their config puts sessman on the rtp and the same session dir.
  vim.fn.mkdir(M.root .. "/config/nvim", "p")
  vim.fn.writefile({
    ("vim.opt.rtp:prepend(%q)"):format(root_dir),
    ("vim.g.sessman_dir = %q"):format(vim.g.sessman_dir),
    "vim.o.swapfile = false",
  }, M.root .. "/config/nvim/init.lua")
  vim.env.XDG_CONFIG_HOME = M.root .. "/config"
  vim.env.XDG_DATA_HOME = M.root .. "/data"
  vim.env.XDG_STATE_HOME = M.root .. "/state"

  M.cwd = vim.fn.getcwd()
  vim.fn.chdir(M.project)

  M.echoed = {}
  vim.api.nvim_echo = function(chunks, ...)
    M.echoed[#M.echoed + 1] = chunks[1][1]
    return originals.echo(chunks, ...)
  end

  M.pids = {}
  return M
end

function M.teardown()
  local sessman = require("sessman")
  for _, s in ipairs(sessman.list()) do
    if s.running and not s.current and not s.unmanaged then
      pcall(function()
        local chan = vim.fn.sockconnect("pipe", s.sock, { rpc = true })
        vim.rpcnotify(chan, "nvim_command", "qall!")
        vim.wait(1000, function()
          return not vim.uv.fs_stat(s.sock)
        end, 10)
        vim.fn.chanclose(chan)
      end)
    end
  end
  pcall(vim.api.nvim_del_augroup_by_name, "sessman_session")
  for _, addr in ipairs(vim.fn.serverlist()) do
    if addr:find(M.run, 1, true) then
      vim.fn.serverstop(addr)
    end
  end

  vim.api.nvim_echo = originals.echo
  vim.fn.confirm = originals.confirm
  vim.env.XDG_RUNTIME_DIR = originals.run
  vim.env.XDG_CONFIG_HOME = originals.config
  vim.env.XDG_DATA_HOME = originals.data
  vim.env.XDG_STATE_HOME = originals.state
  vim.g.sessman_session = nil
  vim.g.sessman_dir = nil
  vim.o.shadafile = "NONE"

  pcall(vim.cmd, "silent! tabonly!")
  pcall(vim.cmd, "silent! only!")
  pcall(vim.cmd, "silent! %bwipeout!")
  vim.fn.chdir(M.cwd)
  vim.fn.delete(M.root, "rf")
  vim.fn.delete(M.run, "rf")
end

--- Write a fake saved session.
---@param project string|false
---@param name string
---@param lines? string[]
function M.write_session(project, name, lines)
  local s = require("sessman").new(project, name)
  vim.fn.mkdir(vim.fs.dirname(s.file), "p")
  vim.fn.writefile(lines or { '" fake session' }, s.file)
  return s
end

---@param answer integer 1 = Yes
function M.stub_confirm(answer)
  local calls = {}
  vim.fn.confirm = function(msg)
    calls[#calls + 1] = msg
    return answer
  end
  return calls
end

--- Replace sessman.connect; records calls.
function M.stub_connect()
  local calls = {}
  require("sessman").connect = function(addr, stop)
    calls[#calls + 1] = { addr = addr, stop = stop }
  end
  return calls
end

--- Evaluate a Lua expression in a running session's server.
function M.remote(sock, expr)
  local chan = vim.fn.sockconnect("pipe", sock, { rpc = true })
  local out = vim.rpcrequest(chan, "nvim_exec_lua", "return " .. expr, {})
  vim.fn.chanclose(chan)
  return out
end

function M.find_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

function M.feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
end

return M
