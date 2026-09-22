local env = require("tests.helpers.env")

describe("project", function()
  local project, events

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    project = env.fresh("sessman.project")
    events = 0
    vim.api.nvim_create_autocmd("User", {
      pattern = "SessmanProjectChanged",
      group = vim.api.nvim_create_augroup("SessmanProjectSpec", { clear = true }),
      callback = function()
        events = events + 1
      end,
    })
  end)

  after_each(function()
    vim.api.nvim_del_augroup_by_name("SessmanProjectSpec")
    env.teardown()
  end)

  describe("get()", function()
    it("returns g:sessman_project as an absolute path with a trailing slash", function()
      assert.equals(env.project .. "/", project.get())
    end)

    it("falls back to the cwd when g:sessman_project is unset", function()
      vim.g.sessman_project = nil
      vim.fn.chdir(env.root)
      assert.equals(env.root .. "/", project.get())
    end)

    it("falls back to the cwd when g:sessman_project is empty", function()
      vim.g.sessman_project = ""
      vim.fn.chdir(env.root)
      assert.equals(env.root .. "/", project.get())
    end)
  end)

  describe("set()", function()
    it("sets g:sessman_project, logs an info event and fires SessmanProjectChanged", function()
      local other = env.root .. "/other"
      vim.fn.mkdir(other, "p")
      project.set(other)
      assert.equals(other .. "/", vim.g.sessman_project)
      assert.equals(1, events)
      -- info.add records the event
      local buf = require("sessman.info").open()
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(buf), 0, -1, false)
      assert.truthy(table.concat(lines, "\n"):find("Project set  " .. other, 1, true))
    end)

    it("expands relative paths", function()
      vim.fn.chdir(env.root)
      vim.fn.mkdir(env.root .. "/rel", "p")
      project.set("rel")
      assert.equals(env.root .. "/rel/", vim.g.sessman_project)
    end)

    it("warns and changes nothing for a non-existent directory", function()
      local notes = env.capture_notify()
      project.set(env.root .. "/missing")
      assert.equals(env.project, vim.g.sessman_project)
      assert.equals(0, events)
      assert.is_true(env.notified(notes, "Invalid directory", vim.log.levels.WARN))
    end)
  end)

  describe("clear()", function()
    it("unsets g:sessman_project and fires SessmanProjectChanged", function()
      project.clear()
      assert.is_nil(vim.g.sessman_project)
      assert.equals(1, events)
    end)
  end)
end)
