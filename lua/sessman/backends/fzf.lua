--- lua/sessman/backends/fzf.lua
--- fzf-lua backend for sessman.nvim

local M = {}

local fzf = require("fzf-lua")

--- Pick a directory for project selection
---@param cb function Callback receiving the selected directory path
function M.pick_directory(cb)
  local home = vim.fn.expand("~")

  fzf.files({
    prompt = "Select Project> ",
    cwd = home,
    fd_opts = [[
      --type d
      --hidden
      --follow
      --exclude .git
      --exclude node_modules
      --exclude .cache
    ]],

    previewer = false,

    actions = {
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

      ["ctrl-d"] = function(selected)
        if not selected or not selected[1] then
          return
        end

        local file = selected[1]
        local path = dir .. "/" .. file

        os.remove(path)
        print("Deleted session: " .. file)
      end,
    },
  })
end

return M
