-- Only commands and one autocmd are defined here; everything else loads on use.

if vim.g.loaded_sessman then
  return
end
vim.g.loaded_sessman = 1

local function complete(arglead)
  return require("sessman").complete(arglead)
end

vim.api.nvim_create_user_command("Session", function(o)
  if o.args == "" then
    require("sessman.buffer").open(o.mods)
  else
    require("sessman").go(o.args)
  end
end, { nargs = "?", complete = complete, desc = "Open the session list, or go to a session" })

vim.api.nvim_create_user_command("SessionSave", function(o)
  require("sessman").save(o.args ~= "" and o.args or nil, { bang = o.bang })
end, { nargs = "?", bang = true, complete = complete, desc = "Save the current session" })

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("sessman_buffer", {}),
  pattern = "sessman://*",
  callback = function(ev)
    require("sessman.buffer").read(ev.buf)
  end,
})
