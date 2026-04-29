local M = {}

local ok = pcall(require, "telescope")
if not ok then
  return M
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local util = require("sessman.util")

-- ------------------------
-- Directory Picker
-- ------------------------
function M.pick_directory(cb)
  local home = vim.fn.expand("~")
  local show_hidden = false

  local start

  start = function()
    local dirs = util.get_dirs({ hidden = show_hidden })

    pickers
      .new({}, {
        prompt_title = show_hidden and "Projects (hidden)" or "Projects",
        cwd = home,

        finder = finders.new_table({
          results = dirs,
        }),

        sorter = conf.generic_sorter({}),

        attach_mappings = function(prompt_bufnr, map)
          local function select()
            local entry = action_state.get_selected_entry()
            actions.close(prompt_bufnr)

            if entry and entry[1] then
              local path = entry[1]

              if not path:match("^/") then
                path = home .. "/" .. path
              end

              cb(vim.fn.fnamemodify(path, ":p"))
            end
          end

          local function toggle_hidden()
            show_hidden = not show_hidden
            actions.close(prompt_bufnr)

            vim.schedule(function()
              start()
            end)
          end

          map("i", "<CR>", select)
          map("n", "<CR>", select)

          map("i", "<C-o>", toggle_hidden)
          map("n", "<C-o>", toggle_hidden)

          return true
        end,
      })
      :find()
  end

  start()
end

-- ------------------------
-- Session Picker
-- ------------------------
function M.pick_session(files, dir, cb)
  pickers
    .new({}, {
      prompt_title = "Sessions",

      finder = finders.new_table({
        results = files,
      }),

      sorter = conf.generic_sorter({}),

      attach_mappings = function(prompt_bufnr, map)
        local function select()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if entry and entry[1] then
            vim.schedule(function()
              cb(entry[1])
            end)
          end
        end

        local function delete()
          local entry = action_state.get_selected_entry()
          if not entry or not entry[1] then
            return
          end

          local file = entry[1]
          local session_mod = require("sessman.session")

          session_mod.delete(file, dir, function()
            if vim.fn.isdirectory(dir) == 0 then
              actions.close(prompt_bufnr)
              return
            end

            local updated = vim.tbl_filter(function(f)
              return f:match("%.vim$")
            end, vim.fn.readdir(dir))

            actions.close(prompt_bufnr)
            vim.schedule(function()
              M.pick_session(updated, dir, cb)
            end)
          end)
        end

        map("i", "<CR>", select)
        map("n", "<CR>", select)

        map("i", "<C-x>", delete)
        map("n", "<C-x>", delete)

        return true
      end,
    })
    :find()
end

return M
