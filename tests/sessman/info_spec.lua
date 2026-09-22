local env = require("tests.helpers.env")

local function buf_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local function info_buf()
  return env.find_buf("sessman://info")
end

describe("info", function()
  local info

  before_each(function()
    env.setup()
    info = env.fresh("sessman.info")
    require("sessman.highlights").setup()
  end)

  after_each(function()
    info.close()
    env.teardown()
  end)

  describe("is_new_load()", function()
    it("accepts the first fire and rejects an immediate repeat for the same path", function()
      assert.is_true(info.is_new_load("Post", "/a.vim"))
      assert.is_false(info.is_new_load("Post", "/a.vim"))
      assert.is_false(info.is_new_load("Post", "/a.vim"))
    end)

    it("tracks Pre and Post independently", function()
      assert.is_true(info.is_new_load("Pre", "/a.vim"))
      assert.is_true(info.is_new_load("Post", "/a.vim"))
      assert.is_false(info.is_new_load("Pre", "/a.vim"))
    end)

    it("treats a different path as a new load", function()
      assert.is_true(info.is_new_load("Post", "/a.vim"))
      assert.is_true(info.is_new_load("Post", "/b.vim"))
    end)

    it("accepts the same path again once the burst window has passed", function()
      assert.is_true(info.is_new_load("Post", "/a.vim"))
      vim.wait(600)
      assert.is_true(info.is_new_load("Post", "/a.vim"))
    end)
  end)

  describe("open/close/toggle", function()
    it("opens a scratch buffer named sessman://info in a new tab", function()
      local tabs = #vim.api.nvim_list_tabpages()
      local win = info.open()
      local buf = vim.api.nvim_win_get_buf(win)
      assert.equals(tabs + 1, #vim.api.nvim_list_tabpages())
      assert.equals("sessman://info", vim.api.nvim_buf_get_name(buf))
      assert.equals("sessman-info", vim.bo[buf].filetype)
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].modifiable)
      assert.is_false(vim.bo[buf].buflisted)
    end)

    it("focuses the existing window instead of opening a second one", function()
      local win = info.open()
      vim.cmd("tabprevious")
      local tabs = #vim.api.nvim_list_tabpages()
      assert.equals(win, info.open())
      assert.equals(win, vim.api.nvim_get_current_win())
      assert.equals(tabs, #vim.api.nvim_list_tabpages())
    end)

    it("close() wipes the buffer", function()
      info.open()
      info.close()
      assert.is_nil(info_buf())
    end)

    it("toggle() opens then closes", function()
      info.toggle()
      assert.is_not_nil(info_buf())
      info.toggle()
      assert.is_nil(info_buf())
    end)

    it("q and <Esc> close the view", function()
      info.open()
      env.feed("q")
      assert.is_nil(info_buf())
      info.open()
      env.feed("<Esc>")
      assert.is_nil(info_buf())
    end)
  end)

  describe("render", function()
    it("shows placeholders when there is no session, global shada and no activity", function()
      vim.o.shadafile = ""
      info.open()
      local text = buf_text(info_buf())
      vim.o.shadafile = "NONE"
      assert.truthy(text:find("Session:  (none)", 1, true))
      assert.truthy(text:find("ShaDa:    (global)", 1, true))
      assert.truthy(text:find("Project:  " .. env.project .. "/", 1, true))
      assert.truthy(text:find("No recent activity", 1, true))
    end)

    it("shows the current session and flags a missing shada file", function()
      vim.v.this_session = "/some/Session.vim"
      vim.o.shadafile = env.root .. "/missing.shada"
      info.open()
      local text = buf_text(info_buf())
      vim.o.shadafile = "NONE"
      assert.truthy(text:find("Session:  /some/Session.vim", 1, true))
      assert.truthy(text:find("missing.shada (not found)", 1, true))
    end)

    it("shows an existing shada file without the (not found) suffix", function()
      local shada = env.root .. "/s.shada"
      vim.fn.writefile({ "" }, shada)
      vim.o.shadafile = shada
      info.open()
      local text = buf_text(info_buf())
      vim.o.shadafile = "NONE"
      assert.truthy(text:find("ShaDa:    " .. shada, 1, true))
      assert.falsy(text:find("(not found)", 1, true))
    end)

    it("add() lists events newest first and re-renders an open view", function()
      info.open()
      info.add("First", "one")
      info.add("Second", "two")
      local lines = vim.api.nvim_buf_get_lines(info_buf(), 0, -1, false)
      local first, second
      for i, l in ipairs(lines) do
        if l == "First  one" then
          first = i
        elseif l == "Second  two" then
          second = i
        end
      end
      assert.is_not_nil(first)
      assert.is_not_nil(second)
      assert.is_true(second < first)
    end)

    it("add() omits the text segment when text is empty", function()
      info.add("Just a kind", "")
      info.open()
      assert.truthy(vim.tbl_contains(vim.api.nvim_buf_get_lines(info_buf(), 0, -1, false), "Just a kind"))
    end)

    it("keeps at most 15 events", function()
      for i = 1, 20 do
        info.add("Event", tostring(i))
      end
      info.open()
      local text = buf_text(info_buf())
      assert.truthy(text:find("Event  20", 1, true))
      assert.truthy(text:find("Event  6\n", 1, true) or text:match("Event  6$"))
      assert.falsy(text:find("Event  5\n", 1, true) or text:match("Event  5$"))
    end)

    it("marks the loaded session with the active icon and older ones with the past icon", function()
      info.add("Loaded Session", "/old.vim")
      info.add("Loaded Session", "/current.vim")
      vim.v.this_session = "/current.vim"
      info.open()
      local lines = vim.api.nvim_buf_get_lines(info_buf(), 0, -1, false)
      assert.truthy(vim.tbl_contains(lines, "●  Loaded Session  /current.vim"))
      assert.truthy(vim.tbl_contains(lines, "○  Loaded Session  /old.vim"))
    end)

    it("uses the configured icons", function()
      require("sessman.config").set({ session_dir = env.session_dir, info = { active_icon = "A", past_icon = "P" } })
      info.add("Loaded ShaDa", "/x.shada")
      info.open()
      assert.truthy(vim.tbl_contains(vim.api.nvim_buf_get_lines(info_buf(), 0, -1, false), "P  Loaded ShaDa  /x.shada"))
    end)

    it("highlights segments with extmarks", function()
      info.open()
      local ns = vim.api.nvim_get_namespaces().sessman_info
      local marks = vim.api.nvim_buf_get_extmarks(info_buf(), ns, 0, -1, { details = true })
      local groups = {}
      for _, m in ipairs(marks) do
        groups[m[4].hl_group] = true
      end
      assert.is_true(groups.SessmanLabel)
      assert.is_true(groups.SessmanSeparator)
      assert.is_true(groups.SessmanComment)
    end)
  end)
end)
