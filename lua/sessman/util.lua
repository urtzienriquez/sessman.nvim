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

return M
