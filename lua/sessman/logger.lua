local M = {}

local log_file = vim.fn.stdpath("state") .. "/sessman-debug.log"

local function should_log()
  return vim.g.sessman_debug == true or vim.env.SESSMAN_DEBUG == "1"
end

local function buf_info(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return { buf = buf, valid = false }
  end

  return {
    buf = buf,
    valid = true,
    name = vim.api.nvim_buf_get_name(buf),
    buftype = vim.bo[buf].buftype,
    filetype = vim.bo[buf].filetype,
    listed = vim.bo[buf].buflisted,
    loaded = vim.api.nvim_buf_is_loaded(buf),
  }
end

local function write(line)
  local f = io.open(log_file, "a")
  if not f then
    return
  end

  f:write(line .. "\n")
  f:close()
end

function M.log(event, buf)
  if not should_log() then
    return
  end

  buf = buf or vim.api.nvim_get_current_buf()
  local info = buf_info(buf)
  local stamp = os.date("%Y-%m-%d %H:%M:%S")

  write(string.format("[%s] %s %s", stamp, event, vim.inspect(info)))
  write(debug.traceback("stack", 3))
  write("")
end

function M.setup()
  local group = vim.api.nvim_create_augroup("SessmanDebugLogger", { clear = true })

  vim.api.nvim_create_autocmd({ "BufAdd", "TermOpen" }, {
    group = group,
    callback = function(args)
      if not should_log() then
        return
      end

      local buf = args.buf or vim.api.nvim_get_current_buf()
      local name = vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or ""

      if name:match("^term://") or vim.bo[buf].buftype == "terminal" then
        M.log(args.event, buf)
      end
    end,
  })
end

return M
