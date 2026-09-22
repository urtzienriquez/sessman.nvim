local M = {}

local ok, pick = pcall(require, "mini.pick")
if not ok then
  return M
end

local util = require("sessman.util")

function M.pick_directory(cb)
  local show_hidden = false

  local function start()
    local dirs = util.get_dirs({ hidden = show_hidden })

    pick.start({
      source = {
        name = show_hidden and "Projects (hidden)" or "Projects",
        items = dirs,

        choose = function(item)
          if not item then
            return
          end
          cb(vim.fn.fnamemodify(item, ":p"))
        end,
      },

      mappings = {
        toggle_hidden = {
          char = "<C-o>",
          func = function()
            show_hidden = not show_hidden
            require("mini.pick").stop()
            vim.schedule(start)
          end,
        },
      },
    })
  end

  start()
end

function M.pick_session(files, dir, cb)
  pick.start({
    source = {
      name = "Sessions",
      items = files,
      choose = function(item)
        if not item then
          return
        end
        vim.schedule(function()
          cb(item)
        end)
      end,
    },

    mappings = {
      delete_session = {
        char = "<C-x>",
        func = function()
          local items = pick.get_picker_matches()
          local current_item = items and items.current
          if not current_item then
            return
          end

          pick.stop() -- lets vim.ui.select take focus

          vim.schedule(function()
            local session_mod = require("sessman.session")

            session_mod.delete(current_item, dir, function()
              if vim.fn.isdirectory(dir) == 0 then
                return
              end

              local updated = vim.tbl_filter(function(f)
                return f:match("%.vim$")
              end, vim.fn.readdir(dir))

              if #updated > 0 then
                M.pick_session(updated, dir, cb)
              else
                vim.notify("No sessions found.", vim.log.levels.INFO)
              end
            end)
          end)
        end,
      },
    },
  })
end

return M
