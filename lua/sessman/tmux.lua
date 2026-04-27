local M = {}

local function nvim_session_command(session_path)
  local escaped = session_path:gsub("%%", "\\%%")
  return "nvim -S '" .. escaped .. "'"
end

function M.update_tmux_resurrect_session()
  local resurrect_dir = vim.fn.trim(vim.fn.system("tmux show-option -gqv @resurrect-dir"))
  if resurrect_dir == "" or vim.v.shell_error ~= 0 then
    return
  end

  local tmux_session = vim.fn.trim(vim.fn.system("tmux display-message -p '#{session_name}'"))
  if vim.v.shell_error ~= 0 or tmux_session == "" then
    return
  end

  local session_path = vim.v.this_session
  if session_path == "" then
    return
  end

  local saved_file = resurrect_dir .. "/saved/" .. tmux_session .. ".resurrect"
  if vim.fn.filereadable(saved_file) == 0 then
    return
  end

  local lines = vim.fn.readfile(saved_file)
  local updated = false
  local session_command = ":" .. nvim_session_command(session_path)

  for i, line in ipairs(lines) do
    local fields = vim.split(line, "\t", { plain = true })
    if fields[1] == "pane" and fields[10] == "nvim" then
      fields[11] = session_command
      lines[i] = table.concat(fields, "\t")
      updated = true
    end
  end

  if updated then
    vim.fn.writefile(lines, saved_file)
  end
end

return M
