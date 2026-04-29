local M = {}

local ok, snacks = pcall(require, "snacks")
if not ok then
  return M
end

-- ------------------------
-- Directory Picker
-- ------------------------
function M.pick_directory(cb)
  local home = vim.fn.expand("~")

  snacks.picker({
    title = "Select Project>",
    prompt = "Select Project> ",

    finder = "files",
    dirs = { home },
    hidden = false,
    follow = true,
    exclude = { ".git", "node_modules", ".cache" },
    args = { "--type", "d" },

    preview = false,

    transform = function(item)
      local stat = vim.loop.fs_stat(item.file)
      return stat and stat.type == "directory" and item or false
    end,

    win = {
      input = {
        keys = {
          ["<C-h>"] = { "toggle_hidden", mode = { "i", "n" } },
        },
      },
    },

    confirm = function(picker, item)
      if not item then
        return
      end

      local path = item.file
      if not path:match("^/") then
        path = home .. "/" .. path
      end

      picker:close()
      cb(vim.fn.fnamemodify(path, ":p"))
    end,
  })
end

-- ------------------------
-- Session Picker
-- ------------------------
function M.pick_session(files, dir, cb)
  local items = vim.tbl_map(function(f)
    return {
      label = f,
      text = f,
      value = f,
    }
  end, files)

  snacks.picker({
    title = "Sessions",
    items = items,

    win = {
      input = {
        keys = {
          ["<C-x>"] = { "delete_session", mode = { "i", "n" } },
        },
      },
    },

    actions = {
      delete_session = function(picker)
        local item = picker:selected({ fallback = true })[1]
        if not item then
          return
        end

        local file = item.value
        local session_mod = require("sessman.session")

        session_mod.delete(file, dir, function()
          if vim.fn.isdirectory(dir) == 0 then
            picker:close()
            return
          end

          local updated = vim.tbl_filter(function(f)
            return f:match("%.vim$")
          end, vim.fn.readdir(dir))

          picker:close()
          vim.schedule(function()
            M.pick_session(updated, dir, cb)
          end)
        end)
      end,
    },

    confirm = function(picker, item)
      if not item then
        return
      end

      picker:close()
      vim.schedule(function()
        cb(item.value)
      end)
    end,
  })
end

return M
