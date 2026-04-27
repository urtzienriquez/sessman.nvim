local M = {}

local session = require("sessman.session")
local project_mod = require("sessman.project")

function M.open()
  vim.cmd("botright split")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  vim.api.nvim_buf_set_name(buf, "sessman://session")

  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "sessman"

  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
  vim.bo[buf].modified = false

  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"

  vim.b[buf].sessman_written = false

  local project = project_mod.get()

  local current_session = vim.v.this_session
  local default_name = "Session.vim"

  if current_session ~= "" then
    default_name = vim.fn.fnamemodify(current_session, ":t")
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Name:",
    default_name,
    "",
    "####################################################################",
    "Project: " .. project,
    "# :w marks as saved",
    "# :q exits",
    "# session only saved if written",
  })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  -- never mark as modified
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
    end,
  })

  -- :w
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.b[buf].sessman_written = true
      vim.bo[buf].modified = false
    end,
  })

  -- exit
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      local should_save = vim.b[buf].sessman_written

      local name = nil
      if should_save and vim.api.nvim_buf_is_valid(buf) then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        name = vim.trim(lines[2] or "")
      end

      vim.schedule(function()
        if should_save then
          session.save(name)
        end

        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end)
    end,
  })

  vim.keymap.set("n", "q", function()
    vim.cmd("q")
  end, { buffer = buf })
end

return M
