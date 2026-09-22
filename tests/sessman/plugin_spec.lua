local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

describe("plugin/sessman.lua", function()
  it("defines the commands on VimEnter and only loads once", function()
    assert.is_nil(vim.g.loaded_sessman)
    vim.cmd.source(root .. "/plugin/sessman.lua")
    assert.equals(1, vim.g.loaded_sessman)

    -- The VimEnter autocmd is registered from a vim.schedule callback
    vim.wait(100, function()
      return #vim.api.nvim_get_autocmds({ event = "VimEnter" }) > 0
    end)
    assert.is_nil(vim.api.nvim_get_commands({}).SessionLoad)
    vim.api.nvim_exec_autocmds("VimEnter", {})
    assert.is_not_nil(vim.api.nvim_get_commands({}).SessionLoad)

    -- A second source is a no-op (no second VimEnter handler)
    vim.cmd.source(root .. "/plugin/sessman.lua")
    vim.wait(50)
    assert.equals(0, #vim.api.nvim_get_autocmds({ event = "VimEnter" }))
  end)
end)
