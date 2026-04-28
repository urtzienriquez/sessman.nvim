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
        fn = function(selected, opts)
          if not selected or not selected[1] then
            return
          end
          local file = selected[1]
          vim.ui.select({ "No", "Yes" }, {
            prompt = "Delete '" .. file .. "'?",
          }, function(choice)
            if choice ~= "Yes" then
              return
            end
            local path = dir .. "/" .. file
            os.remove(path)
            local base = file:gsub("%.vim$", "")
            local shada_path = dir .. "/" .. base .. ".shada"
            if vim.fn.filereadable(shada_path) == 1 then
              os.remove(shada_path)
            end
            vim.api.nvim_echo({
              { "Deleted: ", "DiagnosticWarn" },
              { file, "None" },
            }, false, {})

            -- Get updated file list and reopen picker
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
