local M = {}

function M.setup()
  -- require("sessman.logger").setup()

  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      if not vim.g.sessman_project or vim.g.sessman_project == "" then
        vim.g.sessman_project = vim.fn.getcwd()
      end
    end,
  })

  vim.api.nvim_create_user_command("SessionSave", function()
    require("sessman.ui").open()
  end, {})

  vim.api.nvim_create_user_command("SessionProjectSet", function(opts)
    require("sessman.project").set(opts.args)
  end, { nargs = 1, complete = "dir" })

  vim.api.nvim_create_user_command("SessionProjectClear", function()
    require("sessman.project").clear()
  end, {})

  vim.api.nvim_create_user_command("SessionProjectPick", function()
    require("sessman.picker").pick_project()
  end, {})

  vim.api.nvim_create_user_command("SessionLoad", function()
    require("sessman.picker").pick_session()
  end, {})

  vim.api.nvim_create_user_command("SessionCurrent", function()
    print(require("sessman.session").current_session())
  end, {})

  vim.api.nvim_create_user_command("SessionTmuxSync", function()
    require("sessman.tmux").update_tmux_resurrect_session()
  end, {})

  vim.api.nvim_create_user_command("SessionDebugStart", function()
    vim.g.sessman_debug = true
    print("Sessman debug logging enabled: " .. vim.fn.stdpath("state") .. "/sessman-debug.log")
  end, {})

  vim.api.nvim_create_user_command("SessionDebugStop", function()
    vim.g.sessman_debug = false
    print("Sessman debug logging disabled")
  end, {})
end

return M
