local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

describe("plugin/sessman.lua", function()
  it("only defines commands and an autocmd, loading no module", function()
    vim.cmd.source(root .. "/plugin/sessman.lua")
    assert.equals(1, vim.g.loaded_sessman)

    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds.Session)
    assert.is_not_nil(cmds.S)
    assert.is_nil(cmds.SessionSave)
    assert.equals(1, #vim.api.nvim_get_autocmds({ group = "sessman_buffer", event = "BufReadCmd" }))

    for mod in pairs(package.loaded) do
      assert.is_nil(mod:match("^sessman"), mod .. " loaded at startup")
    end
  end)

  it("is idempotent", function()
    vim.cmd.source(root .. "/plugin/sessman.lua")
    assert.equals(1, #vim.api.nvim_get_autocmds({ group = "sessman_buffer", event = "BufReadCmd" }))
  end)

  it("leaves an existing :S alone (e.g. vim-abolish)", function()
    vim.api.nvim_del_user_command("S")
    vim.api.nvim_create_user_command("S", "echo 'abolish'", { desc = "abolish" })
    vim.g.loaded_sessman = nil
    vim.cmd.source(root .. "/plugin/sessman.lua")
    assert.equals("echo 'abolish'", vim.api.nvim_get_commands({}).S.definition)
  end)
end)
