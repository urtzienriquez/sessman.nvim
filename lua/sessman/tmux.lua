local M = {}

---@return boolean
function M.is_inside_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function nvim_session_command(session_path)
  local escaped = session_path:gsub("%%", "\\%%")
  return "nvim -S '" .. escaped .. "'"
end

local function tmux_output(cmd)
  local out = vim.fn.trim(vim.fn.system(cmd))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out
end

local function parse_resurrect_pane(line)
  local fields = vim.split(line, "\t", { plain = true })
  if #fields < 11 or fields[1] ~= "pane" then
    return nil
  end

  -- Correct field positions (based on your file)
  local window_index = tonumber(fields[3])
  local pane_index = tonumber(fields[4])

  if pane_index == nil or window_index == nil then
    return nil
  end

  return {
    fields = fields,
    session_name = fields[2],
    pane_index = pane_index,
    window_index = window_index,
    cwd = fields[8], -- includes leading ":"
    command = fields[10],
  }
end

function M.update_tmux_resurrect_session()
  if not M.is_inside_tmux() then
    vim.notify("Not running inside a tmux session", vim.log.levels.WARN)
    return
  end

  local resurrect_dir = tmux_output({ "tmux", "show-option", "-gqv", "@resurrect-dir" })
  if not resurrect_dir or resurrect_dir == "" then
    vim.notify("tmux-resurrect is not configured or @resurrect-dir option is not set", vim.log.levels.WARN)
    return
  end

  local tmux_session = tmux_output({ "tmux", "display-message", "-p", "#{session_name}" })
  if not tmux_session or tmux_session == "" then
    return
  end

  local current_window_index_str = tmux_output({ "tmux", "display-message", "-p", "#{window_index}" })
  local current_pane_index_str = tmux_output({ "tmux", "display-message", "-p", "#{pane_index}" })

  if not current_window_index_str or not current_pane_index_str then
    return
  end

  local current_window_index = tonumber(current_window_index_str)
  local current_pane_index = tonumber(current_pane_index_str)

  if not current_window_index or not current_pane_index then
    return
  end

  local session_path = vim.v.this_session
  if session_path == "" then
    vim.notify("No active Neovim session to sync.\n" .. "Save or load a session first", vim.log.levels.WARN)
    return
  end

  local saved_file = resurrect_dir .. "/saved/" .. tmux_session .. ".resurrect"
  if vim.fn.filereadable(saved_file) == 0 then
    vim.notify(
      "tmux session '" .. tmux_session .. "' has not been saved by tmux-resurrect.\n" .. "Skipped sync.",
      vim.log.levels.WARN
    )
    return
  end

  local lines = vim.fn.readfile(saved_file)
  local updated = false
  local session_command = ":" .. nvim_session_command(session_path)

  for i, line in ipairs(lines) do
    if vim.startswith(line, "pane\t") then
      local pane = parse_resurrect_pane(line)

      if
        pane
        and pane.session_name == tmux_session
        and pane.window_index == current_window_index
        and pane.command == "nvim"
      then
        pane.fields[11] = session_command
        lines[i] = table.concat(pane.fields, "\t")
        updated = true
        break
      end
    end
  end

  if updated then
    vim.fn.writefile(lines, saved_file)
    vim.api.nvim_echo({
      { "Synced nvim - tmux resurrect for current pane", "DiagnosticInfo" },
    }, false, {})
  else
    vim.api.nvim_echo({
      { "No matching pane found in resurrect file", "DiagnosticWarn" },
    }, false, {})
  end
end

return M
