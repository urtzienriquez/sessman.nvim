-- Per-test sandbox: temp session dir + project dir, stubs for vim.ui /
-- vim.notify, and fake executables on $PATH.
local M = {}

local originals = {
  select = vim.ui.select,
  input = vim.ui.input,
  notify = vim.notify,
  path = vim.env.PATH,
}

M.root = nil
M.session_dir = nil
M.project = nil

--- Drop a module from the cache and require it again, resetting its
--- module-level state.
---@param mod string
function M.fresh(mod)
  package.loaded[mod] = nil
  return require(mod)
end

--- Resolve symlinks (e.g. /tmp on some systems) so paths compare equal to
--- what getcwd()/fnamemodify(":p") return.
local function realpath(p)
  return vim.uv.fs_realpath(p) or p
end

---@param opts? table Extra config passed to sessman.config.set
function M.setup(opts)
  M.root = realpath(vim.fn.tempname())
  vim.fn.mkdir(M.root, "p")
  M.root = realpath(M.root)
  M.session_dir = M.root .. "/sessions/"
  M.project = M.root .. "/project"
  vim.fn.mkdir(M.project, "p")

  M.cwd = vim.fn.getcwd()

  require("sessman.config").set(vim.tbl_deep_extend("force", { session_dir = M.session_dir }, opts or {}))
  vim.g.sessman_project = M.project
  vim.v.this_session = ""
  vim.o.shadafile = "NONE"

  return M
end

function M.teardown()
  vim.ui.select = originals.select
  vim.ui.input = originals.input
  vim.notify = originals.notify
  vim.env.PATH = originals.path

  pcall(vim.cmd, "silent! tabonly!")
  pcall(vim.cmd, "silent! only!")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  pcall(vim.cmd, "silent! enew!")

  if M.cwd then
    vim.fn.chdir(M.cwd)
  end
  vim.g.sessman_project = nil
  vim.v.this_session = ""
  vim.o.shadafile = "NONE"

  if M.root then
    vim.fn.delete(M.root, "rf")
  end
  M.root, M.session_dir, M.project = nil, nil, nil
end

--- Path of the session directory for the sandbox project.
function M.project_session_dir()
  return M.session_dir .. require("sessman.util").encode_path(M.project)
end

--- Write a fake session file in the sandbox project's session dir.
---@param name string
---@param lines? string[]
---@param mtime? integer
---@return string path
function M.write_session(name, lines, mtime)
  local dir = M.project_session_dir()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/" .. name
  vim.fn.writefile(lines or { '" fake session' }, path)
  if mtime then
    vim.uv.fs_utime(path, mtime, mtime)
  end
  return path
end

--- Replace vim.ui.select with a synchronous stub answering `answer`.
--- Returns a table recording each call's items/opts.
---@param answer any
function M.stub_select(answer)
  local calls = {}
  vim.ui.select = function(items, opts, cb)
    calls[#calls + 1] = { items = items, opts = opts }
    cb(answer)
  end
  return calls
end

---@param answer string|nil
function M.stub_input(answer)
  local calls = {}
  vim.ui.input = function(opts, cb)
    calls[#calls + 1] = opts
    cb(answer)
  end
  return calls
end

--- Record vim.notify calls instead of displaying them.
---@return table[] { { msg, level }, ... }
function M.capture_notify()
  local calls = {}
  vim.notify = function(msg, level)
    calls[#calls + 1] = { msg = msg, level = level }
  end
  return calls
end

--- True if any recorded notification contains `pattern` (plain) at `level`.
function M.notified(calls, pattern, level)
  for _, c in ipairs(calls) do
    if c.msg:find(pattern, 1, true) and (level == nil or c.level == level) then
      return true
    end
  end
  return false
end

--- Write an executable shell script named `name` into a temp bin dir and
--- prepend it to $PATH.
---@param name string
---@param script string Body of the script (a #!/bin/sh line is added)
function M.fake_bin(name, script)
  local bin = (M.root or vim.fn.tempname()) .. "/bin"
  vim.fn.mkdir(bin, "p")
  local path = bin .. "/" .. name
  vim.fn.writefile(vim.split("#!/bin/sh\n" .. script, "\n"), path)
  vim.fn.setfperm(path, "rwxr-xr-x")
  if not vim.env.PATH:find(bin, 1, true) then
    vim.env.PATH = bin .. ":" .. vim.env.PATH
  end
  return path
end

--- Names of all buffers currently displayed in a window.
function M.win_buf_names()
  local names = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    names[#names + 1] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
  end
  return names
end

--- Find a buffer by exact name, or nil.
function M.find_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

--- Run a normal-mode key sequence through the mappings.
function M.feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
end

return M
