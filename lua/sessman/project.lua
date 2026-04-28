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
    vim.api.nvim_echo({
      { "Invalid directory: " .. path, "DiagnosticWarn" },
    }, false, {})
    return
  end

  vim.g.sessman_project = path
  vim.api.nvim_echo({
    { "Sessman project set to: ", "DiagnosticHint" },
    {path, "None"},
  }, false, {})
end

function M.clear()
  vim.g.sessman_project = nil
  vim.api.nvim_echo({
    { "Sessman project cleared", "DiagnosticHint" },
  }, false, {})
end

return M
