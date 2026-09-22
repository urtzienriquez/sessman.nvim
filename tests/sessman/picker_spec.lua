local env = require("tests.helpers.env")

describe("picker", function()
  local picker, backends

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    backends = env.fresh("sessman.backends")
    picker = env.fresh("sessman.picker")
  end)

  after_each(function()
    env.teardown()
  end)

  describe("get_sessions()", function()
    it("returns nil files when the project has no session directory", function()
      local dir, files, local_session = picker.get_sessions()
      assert.equals(env.project_session_dir(), dir)
      assert.is_nil(files)
      assert.equals(env.project .. "/Session.vim", vim.fs.normalize(local_session))
    end)

    it("returns nil files when the directory only holds non-.vim files", function()
      vim.fn.mkdir(env.project_session_dir(), "p")
      vim.fn.writefile({ "" }, env.project_session_dir() .. "/x.shada")
      local _, files = picker.get_sessions()
      assert.is_nil(files)
    end)

    it("returns only .vim files, newest first", function()
      local now = os.time()
      env.write_session("old.vim", nil, now - 100)
      env.write_session("new.vim", nil, now)
      env.write_session("new.shada", nil, now)
      local _, files = picker.get_sessions()
      assert.same({ "new.vim", "old.vim" }, files)
    end)
  end)

  describe("load_session()", function()
    it("refuses to load while listed buffers have unsaved changes", function()
      local notes = env.capture_notify()
      local path = env.write_session("s.vim", { "let g:sessman_spec_loaded = 1" })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "dirty" })
      assert.is_false(picker.load_session(path))
      assert.is_true(env.notified(notes, "[No Name]", vim.log.levels.WARN))
      assert.is_nil(vim.g.sessman_spec_loaded)
      vim.bo.modified = false
    end)

    it("ignores modified scratch (non-file) buffers", function()
      local path = env.write_session("s.vim", { "let g:sessman_spec_loaded = 2" })
      local scratch = vim.api.nvim_create_buf(true, false)
      vim.bo[scratch].buftype = "nofile"
      vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "x" })
      assert.is_true(picker.load_session(path))
      assert.equals(2, vim.g.sessman_spec_loaded)
    end)

    it("fires SessionLoadPre and SessionLoadPost around sourcing", function()
      local fired = {}
      local group = vim.api.nvim_create_augroup("SessmanPickerSpec", { clear = true })
      vim.api.nvim_create_autocmd({ "SessionLoadPre", "SessionLoadPost" }, {
        group = group,
        callback = function(ev)
          fired[#fired + 1] = ev.event
        end,
      })
      local path = env.write_session("s.vim", { "" })
      picker.load_session(path)
      vim.api.nvim_del_augroup_by_id(group)
      assert.equals("SessionLoadPre", fired[1])
      assert.equals("SessionLoadPost", fired[#fired])
    end)

    it("reports an error and returns false when sourcing fails", function()
      local notes = env.capture_notify()
      local path = env.write_session("bad.vim", { "call NoSuchFunction()" })
      assert.is_false(picker.load_session(path))
      assert.is_true(env.notified(notes, "Failed to load session", vim.log.levels.ERROR))
    end)

    it("round-trips a saved session: buffers, tabs and cwd are restored", function()
      local a, b = env.project .. "/a.txt", env.project .. "/b.txt"
      vim.fn.writefile({ "a" }, a)
      vim.fn.writefile({ "b" }, b)
      local sub = env.project .. "/sub"
      vim.fn.mkdir(sub, "p")
      vim.fn.chdir(sub)
      vim.cmd.edit(a)
      vim.cmd.tabedit(b)
      require("sessman.session").save("rt.vim")
      local path = vim.v.this_session

      vim.cmd("silent! tabonly")
      vim.cmd("silent! %bwipeout!")
      vim.fn.chdir(env.root)
      vim.g.sessman_project = nil

      assert.is_true(picker.load_session(path))
      assert.equals(2, #vim.api.nvim_list_tabpages())
      assert.is_not_nil(env.find_buf(a))
      assert.is_not_nil(env.find_buf(b))
      assert.equals(sub, vim.fn.getcwd())
      assert.equals(env.project .. "/", vim.g.sessman_project)
      assert.equals(path, vim.v.this_session)
    end)
  end)

  describe("pick_session()", function()
    it("loads the project-local Session.vim when there are no stored sessions", function()
      vim.fn.writefile({ "let g:sessman_spec_local = 1" }, env.project .. "/Session.vim")
      picker.pick_session()
      assert.equals(1, vim.g.sessman_spec_local)
    end)

    it("warns when there are no sessions at all", function()
      local notes = env.capture_notify()
      picker.pick_session()
      assert.is_true(env.notified(notes, "No sessions for this project", vim.log.levels.WARN))
    end)

    it("hands the files to the backend and loads the chosen one", function()
      env.write_session("one.vim", { "let g:sessman_spec_pick = 'one'" })
      local seen
      backends.register("fzf", {
        pick_session = function(files, dir, cb)
          seen = { files = files, dir = dir }
          cb("one.vim")
        end,
      })
      require("sessman.config").set({ session_dir = env.session_dir, backend = "fzf" })
      picker.pick_session()
      assert.same({ "one.vim" }, seen.files)
      assert.equals(env.project_session_dir(), seen.dir)
      assert.equals("one", vim.g.sessman_spec_pick)
    end)

    it("does nothing when the backend picker is cancelled", function()
      env.write_session("one.vim", { "let g:sessman_spec_cancel = 1" })
      backends.register("fzf", {
        pick_session = function(_, _, cb)
          cb(nil)
        end,
      })
      require("sessman.config").set({ session_dir = env.session_dir, backend = "fzf" })
      picker.pick_session()
      assert.is_nil(vim.g.sessman_spec_cancel)
    end)
  end)

  describe("pick_delete()", function()
    it("deletes a named session directly", function()
      local path = env.write_session("x.vim")
      env.write_session("y.vim")
      local calls = env.stub_select("Yes")
      picker.pick_delete("x.vim")
      assert.equals(1, #calls) -- only the confirmation prompt
      assert.equals(0, vim.fn.filereadable(path))
    end)

    it("falls back to the project-local Session.vim for an unknown name", function()
      local local_session = env.project .. "/Session.vim"
      vim.fn.writefile({ "" }, local_session)
      env.stub_select("Yes")
      picker.pick_delete("nope.vim")
      assert.equals(0, vim.fn.filereadable(local_session))
    end)

    it("warns about an unknown name when there is no local session", function()
      local notes = env.capture_notify()
      picker.pick_delete("nope.vim")
      assert.is_true(env.notified(notes, "Session 'nope.vim' not found", vim.log.levels.WARN))
    end)

    it("warns when there are no sessions and no name was given", function()
      local notes = env.capture_notify()
      picker.pick_delete()
      assert.is_true(env.notified(notes, "No sessions for this project", vim.log.levels.WARN))
    end)

    it("offers the local Session.vim when there are no stored sessions", function()
      local local_session = env.project .. "/Session.vim"
      vim.fn.writefile({ "" }, local_session)
      env.stub_select("Yes")
      picker.pick_delete()
      assert.equals(0, vim.fn.filereadable(local_session))
    end)

    it("lets the user choose which session to delete", function()
      env.write_session("x.vim")
      local keep = env.write_session("y.vim")
      local calls = {}
      vim.ui.select = function(items, opts, cb)
        calls[#calls + 1] = { items = items, opts = opts }
        cb(#calls == 1 and "x.vim" or "Yes")
      end
      picker.pick_delete()
      assert.equals("Delete session", calls[1].opts.prompt)
      assert.equals(0, vim.fn.filereadable(env.project_session_dir() .. "/x.vim"))
      assert.equals(1, vim.fn.filereadable(keep))
    end)
  end)

  describe("pick_project()", function()
    it("sets the project to the directory chosen in the backend", function()
      local other = env.root .. "/other"
      vim.fn.mkdir(other, "p")
      backends.register("fzf", {
        pick_directory = function(cb)
          cb(other)
        end,
      })
      require("sessman.config").set({ session_dir = env.session_dir, backend = "fzf" })
      picker.pick_project()
      assert.equals(other .. "/", vim.g.sessman_project)
    end)

    it("leaves the project alone when cancelled", function()
      backends.register("fzf", {
        pick_directory = function(cb)
          cb(nil)
        end,
      })
      require("sessman.config").set({ session_dir = env.session_dir, backend = "fzf" })
      picker.pick_project()
      assert.equals(env.project, vim.g.sessman_project)
    end)
  end)
end)
