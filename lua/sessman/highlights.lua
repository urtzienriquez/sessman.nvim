local M = {}

function M.setup()
  local hl = vim.api.nvim_set_hl
  local ns = 0

  hl(ns, "SessmanTitle", { link = "Title" })
  hl(ns, "SessmanLabel", { link = "Keyword" })
  hl(ns, "SessmanValue", { link = "Normal" })
  hl(ns, "SessmanComment", { link = "Comment" })
  hl(ns, "SessmanSeparator", { link = "LineNr" })
  hl(ns, "SessmanBoolean", { link = "Boolean" })
end

return M
