local M = {}

function M.encode_path(path)
  path = vim.fn.fnamemodify(path, ":p")
  path = path:gsub("/$", "")
  return path:gsub("/", "%%")
end

function M.sort_by_mtime(dir, files)
  table.sort(files, function(a, b)
    local fa = dir .. "/" .. a
    local fb = dir .. "/" .. b

    return vim.fn.getftime(fa) > vim.fn.getftime(fb)
  end)
end

function M.get_dirs(opts)
  opts = opts or {}

  local home = vim.fn.expand("~")

  local cmd = {
    "fdfind",
    "--type",
    "d",
    "--follow",
    "--exclude",
    ".git",
    "--exclude",
    "node_modules",
    "--exclude",
    ".cache",
  }

  if opts.hidden then
    table.insert(cmd, "--hidden")
  else
    table.insert(cmd, "--no-hidden")
  end

  table.insert(cmd, ".")
  table.insert(cmd, home)

  return vim.fn.systemlist(cmd)
end

return M
