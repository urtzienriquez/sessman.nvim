local M = {}

local fzf = require("fzf-lua")

function M.pick_directory(cb)
  local home = vim.fn.expand("~")

  require("fzf-lua").files({
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

    previewer = false, -- 🔥 KEY FIX

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

function M.pick_session(files, dir, cb)
  require("fzf-lua").fzf_exec(files, {
    prompt = "Sessions> ",
    previewer = false, -- 🔥 KEY FIX

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
