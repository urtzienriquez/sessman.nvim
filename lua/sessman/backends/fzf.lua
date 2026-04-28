--- lua/sessman/backends/fzf.lua
--- fzf-lua backend for sessman.nvim

local M = {}

local fzf = require("fzf-lua")
local actions = require("fzf-lua.actions")

--- Pick a directory for project selection
---@param cb function Callback receiving the selected directory path
function M.pick_directory(cb)
  local home = vim.fn.expand("~")

  fzf.files({
    prompt = "Select Project> ",
    cwd = home,
    hidden = false,
    fd_opts = [[
      --type d
      --follow
      --no-hidden
      --exclude .git
      --exclude node_modules
      --exclude .cache
    ]],

    previewer = false,
    winopts = {
      title = " project directory ",
    },

    actions = {
      ["ctrl-h"] = { fn = actions.toggle_hidden, reuse = true, header = false },

      ["default"] = function(selected, opts)
        if not selected or not selected[1] then
          return
        end

        local path_mod = require("fzf-lua.path")
        local entry = path_mod.entry_to_file(selected[1], opts)
        if not entry then
          return
        end

        local path = entry.path

        if not path:match("^/") then
          path = opts.cwd .. "/" .. path
        end

        cb(vim.fn.fnamemodify(path, ":p"))
      end,
    },
  })
end

--- Pick a session file
---@param files string[] List of session filenames
---@param dir string Directory containing the sessions
---@param cb function Callback receiving the selected filename
function M.pick_session(files, dir, cb)
  fzf.fzf_exec(files, {
    prompt = "Sessions> ",
    previewer = false,
    actions = {
      ["default"] = function(selected)
        if not selected or not selected[1] then
          return
        end
        local file = selected[1]
        vim.schedule(function()
          cb(file)
        end)
      end,
      ["ctrl-d"] = {
        fn = function(selected)
          if not selected or not selected[1] then
            return
          end
          local file = selected[1]
          local session_mod = require("sessman.session")

          session_mod.delete(file, dir, function()
            -- check if directory still exists
            if vim.fn.isdirectory(dir) == 0 then
              -- if last session removed, close the picker by sending esc key
              vim.schedule(function()
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
              end)
              return
            end

            local updated_files = vim.fn.readdir(dir)
            updated_files = vim.tbl_filter(function(f)
              return f:match("%.vim$")
            end, updated_files)

            M.pick_session(updated_files, dir, cb)
          end)
        end,
        reload = true,
        reuse = true,
      },
    },
  })
end

return M
