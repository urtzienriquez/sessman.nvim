-- Only commands and one autocmd are defined here; everything else loads on use.

if vim.g.loaded_sessman then
  return
end
vim.g.loaded_sessman = 1

local opts = {
  nargs = "*",
  bang = true,
  bar = true,
  complete = function(arglead, cmdline)
    return require("sessman").complete(arglead, cmdline)
  end,
  desc = "Sessions: list, switch, new, save, kill, delete",
}
local function command(o)
  require("sessman").command(o)
end

vim.api.nvim_create_user_command("Session", command, opts)
-- Short form, like fugitive's :G. Left alone if :S exists (e.g. vim-abolish).
if vim.fn.exists(":S") ~= 2 then
  vim.api.nvim_create_user_command("S", command, opts)
end

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("sessman_buffer", {}),
  pattern = "sessman://*",
  callback = function(ev)
    require("sessman.buffer").read(ev.buf)
  end,
})
