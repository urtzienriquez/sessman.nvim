local highlights = require("sessman.highlights")

describe("highlights.setup", function()
  local expected = {
    SessmanHeading = "PreProc",
    SessmanLabel = "Conditional",
    SessmanValue = "Normal",
    SessmanPath = "Function",
    SessmanComment = "Comment",
    SessmanSeparator = "LineNrNC",
    SessmanBoolean = "Boolean",
  }

  it("defines every Sessman* group as a link", function()
    highlights.setup()
    for group, link in pairs(expected) do
      local hl = vim.api.nvim_get_hl(0, { name = group, link = true })
      assert.equals(link, hl.link, group)
    end
  end)

  it("restores the links after :highlight clear", function()
    highlights.setup()
    vim.cmd("highlight clear")
    highlights.setup()
    assert.equals("PreProc", vim.api.nvim_get_hl(0, { name = "SessmanHeading", link = true }).link)
  end)
end)
