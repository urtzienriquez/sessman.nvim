local env = require("tests.helpers.env")

describe("model", function()
  local sessman

  before_each(function()
    env.setup()
    sessman = env.fresh("sessman")
  end)

  after_each(env.teardown)

  describe("new()", function()
    it("keeps the %-encoded session layout", function()
      local s = sessman.new("/a/b", "coding")
      assert.equals(env.root .. "/sessions/%a%b/coding.vim", s.file)
      assert.equals(env.root .. "/sessions/%a%b/coding.shada", s.shada)
    end)

    it("puts global sessions in global/", function()
      assert.equals(env.root .. "/sessions/global/notes.vim", sessman.new(false, "notes").file)
    end)

    it("uses a short, stable socket id per identity", function()
      local a, b = sessman.new("/a", "x"), sessman.new("/b", "x")
      assert.equals(12, #vim.fs.basename(a.sock))
      assert.equals(a.sock, sessman.new("/a", "x").sock)
      assert.are_not.equals(a.sock, b.sock)
      assert.are_not.equals(a.sock, sessman.new(false, "x").sock)
    end)
  end)

  describe("list()", function()
    it("finds saved sessions per project and global", function()
      env.write_session(env.project, "coding")
      env.write_session(false, "notes")
      local names = {}
      for _, s in ipairs(sessman.list()) do
        if not s.unmanaged then
          names[#names + 1] = (s.project or "global") .. ":" .. s.name
          assert.is_true(s.saved)
          assert.is_number(s.mtime)
        end
      end
      table.sort(names)
      assert.same({ env.project .. ":coding", "global:notes" }, names)
    end)

    it("ignores unrelated files and directories", function()
      vim.fn.mkdir(env.root .. "/sessions/junk", "p")
      vim.fn.writefile({}, env.root .. "/sessions/junk/x.vim")
      env.write_session(env.project, "coding")
      vim.fn.writefile({}, sessman.new(env.project, "coding").shada)
      local managed = vim.tbl_filter(function(s)
        return not s.unmanaged
      end, sessman.list())
      assert.equals(1, #managed)
    end)

    it("removes stale status files and sockets", function()
      local s = sessman.new(env.project, "dead")
      vim.fn.mkdir(vim.fs.dirname(s.sock), "p")
      vim.fn.writefile({ vim.json.encode({ project = env.project, name = "dead", pid = 1, active = 0 }) }, s.sock .. ".json")
      vim.fn.writefile({}, s.sock)
      for _, o in ipairs(sessman.list()) do
        assert.are_not.equals("dead", o.name)
      end
      assert.is_nil(vim.uv.fs_stat(s.sock .. ".json"))
      assert.is_nil(vim.uv.fs_stat(s.sock))
    end)

    it("marks this instance as a current unmanaged entry", function()
      local cur = vim.tbl_filter(function(s)
        return s.current
      end, sessman.list())
      assert.equals(1, #cur)
      assert.is_true(cur[1].unmanaged)
    end)
  end)

  describe("here()", function()
    it("is the git root, else cwd", function()
      assert.equals(env.project, sessman.here())
      vim.fn.chdir(env.project .. "/sub")
      assert.equals(env.project .. "/sub", sessman.here())
      vim.fn.mkdir(env.project .. "/.git", "p")
      assert.equals(env.project, sessman.here())
    end)

    it("isn't captured by a project with sessions higher up", function()
      env.write_session(env.root, "home") -- like a session saved in ~
      vim.fn.mkdir(env.project .. "/.git", "p")
      vim.fn.chdir(env.project .. "/sub")
      assert.equals(env.project, sessman.here())
    end)
  end)

  describe("resolve() and label()", function()
    before_each(function()
      env.write_session(env.project, "coding")
      env.write_session(false, "notes")
      vim.fn.mkdir(env.root .. "/other", "p")
      env.write_session(env.root .. "/other", "coding")
      env.write_session(env.root .. "/other", "review")
    end)

    local function r(target)
      return sessman.resolve(target, sessman.list())
    end

    it("resolves bare names in the here project, then global", function()
      assert.equals(env.project, r("coding").project)
      assert.is_false(r("notes").project)
      local new = r("brand-new")
      assert.equals(env.project, new.project)
      assert.is_nil(new.saved)
    end)

    it("resolves global/, basename/ and path/ targets", function()
      assert.is_false(r("global/notes").project)
      assert.equals(env.root .. "/other", r("other/review").project)
      assert.equals(env.root .. "/other", r(env.root .. "/other/coding").project)
      assert.equals(env.project .. "/sub", r("./sub/x").project)
    end)

    it("reports unknown and ambiguous projects", function()
      local s, msg = r("nope/x")
      assert.is_nil(s)
      assert.matches("unknown project", msg)
      vim.fn.mkdir(env.root .. "/deep/other", "p")
      env.write_session(env.root .. "/deep/other", "x")
      s, msg = r("other/x")
      assert.is_nil(s)
      assert.matches("ambiguous", msg)
    end)

    it("labels round-trip through resolve", function()
      local sessions = sessman.list()
      local here = sessman.here()
      for _, s in ipairs(sessions) do
        if not s.unmanaged then
          local back = sessman.resolve(sessman.label(s, here, sessions), sessions)
          assert.equals(s.project, back.project)
          assert.equals(s.name, back.name)
        end
      end
    end)

    it("completes labels, fuzzily", function()
      assert.same({ "coding", "global/notes", "other/coding", "other/review" }, sessman.complete(""))
      assert.same({ "other/review" }, sessman.complete("orev"))
    end)
  end)
end)
