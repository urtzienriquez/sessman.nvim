local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

describe("plugin/sessman.lua", function()
  it("only defines commands and an autocmd, loading no module", function()
    vim.cmd.source(root .. "/plugin/sessman.lua")
    assert.equals(1, vim.g.loaded_sessman)

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.Session)
    assert.is_not_nil(cmds.SessionSave)
    assert.equals(1, #vim.api.nvim_get_autocmds({ group = "sessman_buffer", event = "BufReadCmd" }))

    for mod in pairs(package.loaded) do
      assert.is_nil(mod:match("^sessman"), mod .. " loaded at startup")
    end
  end)

  it("is idempotent", function()
    vim.cmd.source(root .. "/plugin/sessman.lua")
    assert.equals(1, #vim.api.nvim_get_autocmds({ group = "sessman_buffer", event = "BufReadCmd" }))
  end)
end)
