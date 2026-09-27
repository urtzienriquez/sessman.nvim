local env = require("tests.helpers.env")

describe(":Session save", function()
  local sessman

  before_each(function()
    env.setup()
    sessman = env.fresh("sessman")
  end)

  after_each(env.teardown)

  it("needs a name in a plain nvim", function()
    sessman.save()
    assert.matches("argument required", env.echoed[#env.echoed])
  end)

  it("adopts a plain nvim: writes the file and becomes running", function()
    vim.cmd.edit(env.project .. "/a.txt")
    sessman.save("mine")
    local s = sessman.current()
    assert.same({ project = env.project, name = "mine" }, vim.g.sessman_session)
    assert.equals(1, vim.fn.filereadable(s.file))
    assert.matches("a%.txt", table.concat(vim.fn.readfile(s.file), "\n"))
    assert.is_true(vim.tbl_contains(vim.fn.serverlist(), s.sock))
    assert.equals(1, vim.fn.filereadable(s.sock .. ".json"))
    local listed = sessman.resolve("mine", sessman.list())
    assert.is_true(listed.current and listed.running and listed.saved)
  end)

  it("refuses to overwrite an existing session without !", function()
    env.write_session(env.project, "taken", { "original" })
    sessman.save("taken")
    assert.matches("add ! to override", env.echoed[#env.echoed])
    assert.is_nil(vim.g.sessman_session)
    sessman.save("taken", { bang = true })
    assert.are_not.same({ "original" }, vim.fn.readfile(sessman.new(env.project, "taken").file))
  end)

  it("adopts into global: and path targets", function()
    sessman.save("global:notes")
    assert.is_false(sessman.current().project)
  end)

  it("saves the current session in place, but never renames it", function()
    sessman.save("mine")
    sessman.save()
    sessman.save("mine")
    sessman.save("other")
    assert.matches("can't change", env.echoed[#env.echoed])
  end)

  it("writes ShaDa only when asked or already in use", function()
    sessman.save("mine")
    local s = sessman.current()
    assert.equals(0, vim.fn.filereadable(s.shada))
    sessman.save(nil, { shada = true })
    assert.equals(1, vim.fn.filereadable(s.shada))
    assert.equals(s.shada, vim.o.shadafile)
  end)

  it("never records the session buffer, even as the only window", function()
    vim.cmd("runtime plugin/sessman.lua")
    vim.cmd("Session")
    vim.cmd("only")
    assert.equals(1, #vim.api.nvim_list_wins())
    sessman.save("mine")
    local file = table.concat(vim.fn.readfile(sessman.current().file), "\n")
    assert.is_nil(file:find("sessman://", 1, true))
    assert.is_nil(env.find_buf("sessman://sessions"))
  end)

  it("drops a stale sessman:// buffer restored by an old session file", function()
    vim.cmd("enew | file sessman://sessions")
    vim.cmd("split " .. vim.fn.fnameescape(env.project .. "/a.txt"))
    sessman.save("mine")
    local file = table.concat(vim.fn.readfile(sessman.current().file), "\n")
    assert.is_nil(file:find("sessman://", 1, true))
    assert.matches("a%.txt", file)
  end)

  it("closes the session buffer so it isn't recorded", function()
    vim.cmd("runtime plugin/sessman.lua")
    vim.cmd.edit(env.project .. "/a.txt")
    vim.cmd("Session")
    sessman.save("mine")
    assert.is_nil(env.find_buf("sessman://sessions"))
    assert.is_nil(table.concat(vim.fn.readfile(sessman.current().file), "\n"):find("sessman://", 1, true))
  end)

  describe("g:sessman_exclude", function()
    after_each(function()
      vim.g.sessman_exclude = nil
    end)

    --- Layout: a.txt | R-console / terminal running `sleep 30`
    local function layout()
      vim.cmd("runtime plugin/sessman.lua")
      vim.cmd.edit(env.project .. "/a.txt")
      vim.cmd("vsplit | enew | file R-console | split | terminal sleep 30")
      local term = vim.api.nvim_get_current_buf()
      return term, env.find_buf(env.project .. "/R-console")
    end

    local function names()
      return vim.tbl_map(function(w)
        return vim.fs.basename(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)))
      end, vim.api.nvim_list_wins())
    end

    it("leaves matching buffers out of the file, and puts everything back", function()
      vim.g.sessman_exclude = { "R-console", "term://*:sleep*" }
      local term, rcons = layout()
      vim.bo[rcons].buflisted = true
      local before = names()
      sessman.save("mine")

      local file = table.concat(vim.fn.readfile(sessman.current().file), "\n")
      assert.is_nil(file:find("R-console", 1, true))
      assert.is_nil(file:find("term://", 1, true))
      assert.matches("a%.txt", file)

      assert.same(before, names())
      assert.equals(-1, vim.fn.jobwait({ vim.bo[term].channel }, 0)[1], "terminal still runs")
      assert.is_true(vim.bo[rcons].buflisted)
      assert.is_nil(env.find_buf("sessman://excluded"))
    end)

    it("restores the layout without the excluded windows", function()
      vim.g.sessman_exclude = { "R-console", "term://*:sleep*" }
      layout()
      sessman.save("mine")
      local file = sessman.current().file

      vim.cmd("silent! %bwipeout!")
      vim.cmd("source " .. vim.fn.fnameescape(file))
      vim.wait(200, function()
        return #vim.api.nvim_list_wins() == 1
      end)
      assert.same({ "a.txt" }, names())
      assert.is_nil(env.find_buf("sessman://excluded"))
    end)

    it("matches the tail, or the full name when the pattern has a /", function()
      vim.g.sessman_exclude = { "*.log", env.project .. "/keep/*" }
      vim.cmd.edit(env.project .. "/a.txt")
      vim.cmd("badd " .. env.project .. "/x.log | badd " .. env.project .. "/keep/b.txt | badd " .. env.project .. "/c.txt")
      sessman.save("mine")
      local file = table.concat(vim.fn.readfile(sessman.current().file), "\n")
      assert.is_nil(file:find("x.log", 1, true))
      assert.is_nil(file:find("b.txt", 1, true))
      assert.matches("c%.txt", file)
    end)
  end)
end)
