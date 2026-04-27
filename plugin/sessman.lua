--- plugin/sessman.lua
--- Entry point for sessman.nvim - loaded automatically by Neovim

if vim.g.loaded_sessman == 1 then
  return
end
vim.g.loaded_sessman = 1

-- Defer loading until VimEnter to avoid impacting startup time
vim.schedule(function()
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      -- Initialize sessman after Neovim has fully started
      local ok, sessman = pcall(require, "sessman")
      if ok then
        sessman.init()
      else
        vim.notify("sessman: failed to load - " .. tostring(sessman), vim.log.levels.ERROR)
      end
    end,
    once = true,
  })
end)
