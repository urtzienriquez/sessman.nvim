local env = require("tests.helpers.env")

describe("session", function()
  local session

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    session = env.fresh("sessman.session")
  end)

  after_each(function()
    env.teardown()
  end)

  describe("save()", function()
    it("writes Session.vim under <session_dir>/<encoded project>/ by default", function()
      session.save()
      local path = env.project_session_dir() .. "/Session.vim"
      assert.equals(1, vim.fn.filereadable(path))
      assert.equals(path, vim.v.this_session)
    end)

    it("saves inside session_dir even when it was configured without a trailing slash", function()
      require("sessman.config").set({ session_dir = env.root .. "/sessions" })
      session.save()
      assert.equals(1, vim.fn.filereadable(env.project_session_dir() .. "/Session.vim"))
      local _, files = require("sessman.picker").get_sessions()
      assert.same({ "Session.vim" }, files)
    end)

    it("uses the given name", function()
      session.save("work.vim")
      assert.equals(1, vim.fn.filereadable(env.project_session_dir() .. "/work.vim"))
    end)

    it("treats an empty name as Session.vim", function()
      session.save("")
      assert.equals(1, vim.fn.filereadable(env.project_session_dir() .. "/Session.vim"))
    end)

    it("prepends the project/cwd globals and appends the cd line", function()
      local sub = env.project .. "/sub"
      vim.fn.mkdir(sub, "p")
      vim.fn.chdir(sub)
      session.save()
      local lines = vim.fn.readfile(env.project_session_dir() .. "/Session.vim")
      assert.equals('let g:sessman_project = "' .. env.project .. '/"', lines[1])
      assert.equals('let g:sessman_cwd = "' .. sub .. '"', lines[2])
      assert.equals('if exists("g:sessman_cwd") | execute "cd " . fnameescape(g:sessman_cwd) | endif', lines[#lines])
    end)

    it("restores the cwd and sessionoptions afterwards", function()
      vim.fn.chdir(env.root)
      local so = vim.o.sessionoptions
      session.save()
      assert.equals(env.root, vim.fn.getcwd())
      assert.equals(so, vim.o.sessionoptions)
    end)

    it("records open file buffers in the session", function()
      local file = env.project .. "/hello.txt"
      vim.fn.writefile({ "hi" }, file)
      vim.cmd.edit(file)
      session.save()
      local text = table.concat(vim.fn.readfile(env.project_session_dir() .. "/Session.vim"), "\n")
      assert.truthy(text:find("hello.txt", 1, true))
    end)

    it("writes a sibling .shada and switches shadafile when shada = true", function()
      session.save("s.vim", { shada = true })
      local shada = env.project_session_dir() .. "/s.shada"
      assert.equals(1, vim.fn.filereadable(shada))
      assert.equals(shada, vim.o.shadafile)
    end)

    it("does not write a .shada without the option", function()
      session.save("s.vim")
      assert.equals(0, vim.fn.filereadable(env.project_session_dir() .. "/s.shada"))
    end)

    it("logs Saved Session / Saved ShaDa events", function()
      session.save("s.vim", { shada = true })
      local win = require("sessman.info").open()
      local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
      assert.truthy(text:find("Saved Session", 1, true))
      assert.truthy(text:find("Saved ShaDa", 1, true))
    end)

    it("refuses to save when the project directory does not exist", function()
      vim.g.sessman_project = env.root .. "/gone"
      session.save()
      assert.equals(0, vim.fn.isdirectory(env.session_dir))
      assert.equals("", vim.v.this_session)
    end)

    it("asks before overwriting and overwrites on Yes", function()
      local path = env.write_session("Session.vim", { "old" })
      local calls = env.stub_select("Yes")
      session.save()
      assert.equals(1, #calls)
      assert.same({ "No", "Yes" }, calls[1].items)
      assert.are_not.same({ "old" }, vim.fn.readfile(path))
    end)

    it("leaves the existing file untouched on No", function()
      local path = env.write_session("Session.vim", { "old" })
      env.stub_select("No")
      session.save()
      assert.same({ "old" }, vim.fn.readfile(path))
    end)

    it("leaves the existing file untouched when the prompt is cancelled", function()
      local path = env.write_session("Session.vim", { "old" })
      env.stub_select(nil)
      session.save()
      assert.same({ "old" }, vim.fn.readfile(path))
    end)

    it("does not record sessman windows and reopens the session list", function()
      require("sessman.list").open()
      require("sessman.info").open()
      vim.cmd("tabfirst")
      session.save()
      local text = table.concat(vim.fn.readfile(env.project_session_dir() .. "/Session.vim"), "\n")
      assert.falsy(text:find("sessman://", 1, true))
      assert.is_not_nil(env.find_buf("sessman://sessions"))
      assert.is_nil(env.find_buf("sessman://info"))
    end)
  end)

  describe("save_current()", function()
    it("opens the save UI when no session is loaded", function()
      session.save_current()
      assert.is_not_nil(env.find_buf("sessman://session"))
    end)

    it("opens the save UI when the loaded session belongs to another project", function()
      vim.v.this_session = env.root .. "/elsewhere/Session.vim"
      session.save_current()
      assert.is_not_nil(env.find_buf("sessman://session"))
    end)

    it("re-saves the loaded session in place after confirming", function()
      local path = env.write_session("work.vim", { "old" })
      vim.v.this_session = path
      local calls = env.stub_select("Yes")
      session.save_current()
      assert.equals(1, #calls)
      assert.truthy(calls[1].opts.prompt:find("work.vim", 1, true))
      assert.are_not.same({ "old" }, vim.fn.readfile(path))
      assert.is_nil(env.find_buf("sessman://session"))
    end)

    it("also rewrites the shada when the session's shada is in use", function()
      local path = env.write_session("work.vim")
      local shada = env.project_session_dir() .. "/work.shada"
      vim.v.this_session = path
      vim.o.shadafile = shada
      env.stub_select("Yes")
      session.save_current()
      assert.equals(1, vim.fn.filereadable(shada))
    end)

    it("does not write a shada when a different one is in use", function()
      local path = env.write_session("work.vim")
      vim.v.this_session = path
      env.stub_select("Yes")
      session.save_current()
      assert.equals(0, vim.fn.filereadable(env.project_session_dir() .. "/work.shada"))
    end)
  end)

  describe("delete()", function()
    it("removes the session and its shada on Yes, and calls on_complete", function()
      env.write_session("a.vim")
      env.write_session("b.vim")
      local dir = env.project_session_dir()
      vim.fn.writefile({ "" }, dir .. "/a.shada")
      env.stub_select("Yes")
      local done = false
      session.delete("a.vim", dir, function()
        done = true
      end)
      assert.is_true(done)
      assert.equals(0, vim.fn.filereadable(dir .. "/a.vim"))
      assert.equals(0, vim.fn.filereadable(dir .. "/a.shada"))
      assert.equals(1, vim.fn.filereadable(dir .. "/b.vim"))
    end)

    it("clears v:this_session and shadafile when they point at the deleted files", function()
      local path = env.write_session("a.vim")
      local dir = env.project_session_dir()
      vim.fn.writefile({ "" }, dir .. "/a.shada")
      vim.v.this_session = path
      vim.o.shadafile = dir .. "/a.shada"
      env.stub_select("Yes")
      session.delete("a.vim", dir)
      assert.equals("", vim.v.this_session)
      assert.equals("", vim.o.shadafile)
    end)

    it("removes the project's session directory when it becomes empty", function()
      env.write_session("a.vim")
      local dir = env.project_session_dir()
      env.stub_select("Yes")
      session.delete("a.vim", dir)
      assert.equals(0, vim.fn.isdirectory(dir))
    end)

    it("keeps everything on No but still calls on_complete", function()
      local path = env.write_session("a.vim")
      env.stub_select("No")
      local done = false
      session.delete("a.vim", env.project_session_dir(), function()
        done = true
      end)
      assert.is_true(done)
      assert.equals(1, vim.fn.filereadable(path))
    end)

    it("reports an error when the file cannot be removed", function()
      vim.fn.mkdir(env.project_session_dir(), "p")
      env.write_session("keep.vim")
      local notes = env.capture_notify()
      env.stub_select("Yes")
      session.delete("missing.vim", env.project_session_dir())
      assert.is_true(env.notified(notes, "Failed to delete session", vim.log.levels.ERROR))
    end)
  end)

  describe("current_session()", function()
    it("toggles the info view", function()
      session.current_session()
      assert.is_not_nil(env.find_buf("sessman://info"))
      session.current_session()
      assert.is_nil(env.find_buf("sessman://info"))
    end)
  end)
end)
