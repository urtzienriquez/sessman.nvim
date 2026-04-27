local M = {}

function M.get()
  if vim.g.sessman_project and vim.g.sessman_project ~= "" then
    return vim.fn.fnamemodify(vim.g.sessman_project, ":p")
  end
  return vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
end

function M.set(path)
  path = vim.fn.fnamemodify(path, ":p")

  if vim.fn.isdirectory(path) == 0 then
    print("Invalid directory: " .. path)
    return
  end

  vim.g.sessman_project = path
  print("Sessman project set to: " .. path)
end

function M.clear()
  vim.g.sessman_project = nil
  print("Sessman project cleared")
end

return M
