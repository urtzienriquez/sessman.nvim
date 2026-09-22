local env = require("tests.helpers.env")
local util = require("sessman.util")

describe("util.encode_path", function()
  it("replaces every / with %", function()
    assert.equals("%home%user%project", (util.encode_path("/home/user/project")))
  end)

  it("strips a trailing slash before encoding", function()
    assert.equals("%home%user%project", (util.encode_path("/home/user/project/")))
  end)

  it("expands relative paths against the cwd", function()
    local cwd = vim.fn.getcwd()
    local expected = (cwd .. "/sub"):gsub("/", "%%")
    assert.equals(expected, (util.encode_path("sub")))
  end)

  it("encodes the root directory to an empty string", function()
    assert.equals("", (util.encode_path("/")))
  end)
end)

describe("util.sort_by_mtime", function()
  before_each(function()
    env.setup()
  end)

  after_each(function()
    env.teardown()
  end)

  it("sorts files newest first", function()
    local dir = env.root
    local now = os.time()
    for name, age in pairs({ ["old.vim"] = 300, ["new.vim"] = 0, ["mid.vim"] = 100 }) do
      local p = dir .. "/" .. name
      vim.fn.writefile({ "" }, p)
      vim.uv.fs_utime(p, now - age, now - age)
    end
    local files = { "old.vim", "mid.vim", "new.vim" }
    util.sort_by_mtime(dir, files)
    assert.same({ "new.vim", "mid.vim", "old.vim" }, files)
  end)
end)

describe("util.get_dirs", function()
  before_each(function()
    env.setup()
    -- Echo each argument on its own line so the tests can inspect argv.
    env.fake_bin("fdfind", 'for a in "$@"; do echo "$a"; done')
  end)

  after_each(function()
    env.teardown()
  end)

  it("excludes hidden directories by default and searches $HOME", function()
    local args = util.get_dirs()
    assert.is_true(vim.tbl_contains(args, "--no-hidden"))
    assert.is_false(vim.tbl_contains(args, "--hidden"))
    assert.same({ "--type", "d", "--follow" }, { args[1], args[2], args[3] })
    assert.equals(vim.fn.expand("~"), args[#args])
    assert.equals(".", args[#args - 1])
  end)

  it("excludes .git, node_modules and .cache", function()
    local args = table.concat(util.get_dirs(), " ")
    assert.truthy(args:find("--exclude .git", 1, true))
    assert.truthy(args:find("--exclude node_modules", 1, true))
    assert.truthy(args:find("--exclude .cache", 1, true))
  end)

  it("passes --hidden when opts.hidden is set", function()
    local args = util.get_dirs({ hidden = true })
    assert.is_true(vim.tbl_contains(args, "--hidden"))
    assert.is_false(vim.tbl_contains(args, "--no-hidden"))
  end)
end)
