local M = {}

local session = require("sessman.session")
local project_mod = require("sessman.project")

local state = {
  buf = nil,
  data = {
    name = "",
    write_shada = false,
    project = "",
  },
}

local ns_id = vim.api.nvim_create_namespace("sessman")

local function apply_highlights(buf, data)
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local function hi_text(line_idx, query, group)
    local text = lines[line_idx + 1] or ""
    local s, e = text:find(query, 1, true)
    if s then
      vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, s - 1, {
        end_col = e,
        hl_group = group,
      })
    end
  end

  local function hi_line(line_idx, group)
    if not lines[line_idx + 1] then
      return
    end
    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
      end_col = #lines[line_idx + 1],
      hl_group = group,
    })
  end

  hi_line(0, "SessmanTitle")
  hi_text(2, "Name:", "SessmanLabel")
  hi_text(2, data.name, "SessmanValue")
  hi_text(3, "Write shada?", "SessmanLabel")
  hi_text(3, data.write_shada and "yes" or "no", "SessmanBoolean")
  hi_line(5, "SessmanSeparator")
  hi_text(6, "Project:", "SessmanLabel")
  hi_text(6, data.project, "SessmanValue")

  for i = 8, #lines - 1 do
    hi_line(i, "SessmanComment")
  end
end

local function render()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  -- Temporarily lift restrictions to write content
  vim.bo[state.buf].modifiable = true
  vim.bo[state.buf].readonly = false

  local lines = {
    "Session",
    "",
    string.format("Name:        %s", state.data.name),
    string.format("Write shada? %s", state.data.write_shada and "yes" or "no"),
    "",
    "────────────────────────────────────────",
    string.format("Project: %s", state.data.project),
    "",
    "# Commands:",
    "# <CR>  Toggle/Edit option",
    "# s     Save session",
    "# q     Close",
    "# g?    Help (press q to return)",
  }

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].readonly = true

  apply_highlights(state.buf, state.data)
end

local function toggle_option()
  local line_text = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)

  if line_text:match("Write shada%?") then
    state.data.write_shada = not state.data.write_shada
    render()
  elseif line_text:match("Name:") then
    vim.ui.input({
      prompt = "Rename session (without .vim): ",
    }, function(input)
      if input and input ~= "" then
        state.data.name = input .. ".vim"
        render()
      end
    end)
  end
  pcall(vim.api.nvim_win_set_cursor, 0, cursor)
end

function M.open()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local win = vim.fn.bufwinid(state.buf)
    if win ~= -1 then
      vim.api.nvim_set_current_win(win)
      return
    end
  end

  if vim.o.splitbelow then
    vim.cmd("botright split")
  else
    vim.cmd("topleft split")
  end

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, state.buf)

  pcall(vim.api.nvim_buf_set_name, state.buf, "sessman://session")

  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].filetype = "sessman"
  vim.bo[state.buf].bufhidden = "wipe"

  state.data = {
    name = vim.fn.fnamemodify(vim.v.this_session ~= "" and vim.v.this_session or "Session.vim", ":t"),
    write_shada = false,
    project = project_mod.get(),
  }

  render()

  local opts = { buffer = state.buf, silent = true, nowait = true }

  vim.keymap.set("n", "<CR>", toggle_option, opts)

  vim.keymap.set("n", "s", function()
    vim.cmd("close")
    session.save(state.data.name, { shada = state.data.write_shada })
  end, opts)

  vim.keymap.set("n", "q", "<Cmd>close<CR>", opts)
  vim.keymap.set("n", "g?", "<Cmd>help sessman-maps<CR>", opts)
  vim.keymap.set("n", "]c", function()
    vim.fn.search([[\v^\w+:]], "W")
  end, opts)
  vim.keymap.set("n", "[c", function()
    vim.fn.search([[\v^\w+:]], "bW")
  end, opts)

  vim.api.nvim_win_set_cursor(0, { 3, 13 })
end

return M
