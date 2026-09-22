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
    vim.notify("Invalid directory: " .. path, vim.log.levels.WARN)
    return
  end

  vim.g.sessman_project = path
  require("sessman.info").add("Project set", path, "DiagnosticHint")
  vim.api.nvim_exec_autocmds("User", { pattern = "SessmanProjectChanged" })
end

function M.clear()
  vim.g.sessman_project = nil
  require("sessman.info").add("Project cleared", vim.fn.getcwd(), "DiagnosticHint")
  vim.api.nvim_exec_autocmds("User", { pattern = "SessmanProjectChanged" })
end

return M
