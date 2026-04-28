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

  vim.b[buf].sessman_written = false

  local project = project_mod.get()

  local current_session = vim.v.this_session
  local default_name = "Session.vim"

  if current_session ~= "" then
    default_name = vim.fn.fnamemodify(current_session, ":t")
  end

  local content = {
    "Session",
    "",
    "Name:        " .. default_name,
    "Write shada? no",
    "",
    "────────────────────────────────────────",
    "Project: " .. project,
    "# :w marks as saved",
    "# :q exits",
    "# session only saved if written",
    "# change 'no' to 'yes' to save shada",
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  -- highlights
  local ns = vim.api.nvim_create_namespace("sessman")

  local function hi(line, col_start, col_end, group)
    if col_end == -1 then
      local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
      col_end = #text
    end

    vim.api.nvim_buf_set_extmark(buf, ns, line, col_start, {
      end_col = col_end,
      hl_group = group,
    })
  end

  local function hi_match(line, pattern, group)
    local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
    local s, e = text:find(pattern)

    if s then
      vim.api.nvim_buf_set_extmark(buf, ns, line, s - 1, {
        end_col = e,
        hl_group = group,
      })
    end
  end

  hi(0, 0, -1, "SessmanTitle")
  hi_match(2, "Name:", "SessmanLabel")
  hi_match(2, default_name, "SessmanValue")
  hi_match(3, "Write shada%?", "SessmanLabel")
  hi_match(3, "%f[%w]no%f[%W]", "SessmanBoolean")
  hi(5, 0, -1, "SessmanSeparator")
  hi_match(6, "Project:", "SessmanLabel")
  hi_match(6, project, "SessmanValue")
  for i = 7, #content - 1 do
    hi(i, 0, -1, "SessmanComment")
  end

  vim.api.nvim_win_set_cursor(0, { 3, 13 })

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
      local write_shada = false

      if should_save and vim.api.nvim_buf_is_valid(buf) then
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        local name_line = lines[3] or ""
        name = vim.trim(name_line:match("^Name:%s*(.+)$") or "")

        local shada_line = vim.trim(lines[4] or ""):lower()
        write_shada = shada_line:match("yes") ~= nil
      end

      vim.schedule(function()
        if should_save then
          session.save(name, { shada = write_shada })
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
