local env = require("tests.helpers.env")

local function fresh_config()
  return env.fresh("sessman.config")
end

describe("config.set / config.get", function()
  after_each(function()
    env.teardown()
  end)

  it("applies the defaults when called with no options", function()
    local config = fresh_config()
    config.set()
    local opts = config.get()
    assert.is_nil(opts.backend)
    assert.equals("auto", opts.project_detection)
    assert.equals("●", opts.info.active_icon)
    assert.equals("○", opts.info.past_icon)
    assert.equals("DiagnosticOk", opts.info.active_highlight)
  end)

  it("defaults session_dir to stdpath('data')/session/", function()
    local config = fresh_config()
    config.set({})
    assert.equals(vim.fn.stdpath("data") .. "/session/", config.get().session_dir)
  end)

  it("keeps an explicit session_dir", function()
    local config = fresh_config()
    config.set({ session_dir = "/tmp/somewhere/" })
    assert.equals("/tmp/somewhere/", config.get().session_dir)
  end)

  it("adds a trailing slash to session_dir when missing", function()
    local config = fresh_config()
    config.set({ session_dir = "/tmp/somewhere" })
    assert.equals("/tmp/somewhere/", config.get().session_dir)
  end)

  it("collapses repeated trailing slashes in session_dir", function()
    local config = fresh_config()
    config.set({ session_dir = "/tmp/somewhere//" })
    assert.equals("/tmp/somewhere/", config.get().session_dir)
  end)

  it("expands ~ in session_dir", function()
    local config = fresh_config()
    config.set({ session_dir = "~/sessions" })
    assert.equals(vim.fn.expand("~") .. "/sessions/", config.get().session_dir)
  end)

  it("treats an empty session_dir as the default", function()
    local config = fresh_config()
    config.set({ session_dir = "" })
    assert.equals(vim.fn.stdpath("data") .. "/session/", config.get().session_dir)
  end)

  it("deep-merges nested info options instead of replacing them", function()
    local config = fresh_config()
    config.set({ info = { active_icon = "*" } })
    local opts = config.get()
    assert.equals("*", opts.info.active_icon)
    assert.equals("○", opts.info.past_icon)
    assert.equals("DiagnosticOk", opts.info.active_highlight)
  end)

  it("does not mutate M.defaults across repeated set() calls", function()
    local config = fresh_config()
    config.set({ project_detection = "manual", info = { past_icon = "x" } })
    config.set({})
    assert.equals("auto", config.get().project_detection)
    assert.equals("○", config.get().info.past_icon)
    assert.is_nil(config.defaults.session_dir)
  end)

  for _, name in ipairs({ "fzf", "telescope", "minipick", "snacks" }) do
    it("accepts backend '" .. name .. "'", function()
      local notes = env.capture_notify()
      local config = fresh_config()
      config.set({ backend = name })
      assert.equals(name, config.get().backend)
      assert.equals(0, #notes)
    end)
  end

  it("warns about and drops an unknown backend", function()
    local notes = env.capture_notify()
    local config = fresh_config()
    config.set({ backend = "bogus" })
    assert.is_nil(config.get().backend)
    assert.is_true(env.notified(notes, "unknown backend 'bogus'", vim.log.levels.WARN))
  end)

  it("get() auto-initializes with defaults when set() was never called", function()
    local config = fresh_config()
    local opts = config.get()
    assert.equals("auto", opts.project_detection)
    assert.equals(vim.fn.stdpath("data") .. "/session/", opts.session_dir)
  end)

  it("get() auto-initialization does not share tables with M.defaults", function()
    local config = fresh_config()
    config.get().info.active_icon = "changed"
    assert.equals("●", config.defaults.info.active_icon)
  end)
end)

describe("config.detect_backend", function()
  local fakes = { "fzf-lua", "telescope", "mini.pick", "snacks" }
  local saved = {}

  before_each(function()
    for _, mod in ipairs(fakes) do
      saved[mod] = package.loaded[mod]
      package.loaded[mod] = nil
    end
  end)

  after_each(function()
    for _, mod in ipairs(fakes) do
      package.loaded[mod] = saved[mod]
    end
  end)

  it("returns the explicitly configured backend", function()
    local config = fresh_config()
    config.set({ backend = "snacks" })
    package.loaded["fzf-lua"] = {}
    assert.equals("snacks", config.detect_backend())
  end)

  it("works before set()/get() has been called", function()
    local config = fresh_config()
    package.loaded["snacks"] = {}
    assert.equals("snacks", config.detect_backend())
  end)

  it("returns nil when no picker plugin is installed", function()
    local config = fresh_config()
    config.set({})
    assert.is_nil(config.detect_backend())
  end)

  local order = {
    { "fzf-lua", "fzf" },
    { "telescope", "telescope" },
    { "mini.pick", "minipick" },
    { "snacks", "snacks" },
  }

  for i, pair in ipairs(order) do
    it("detects " .. pair[1] .. " when it is the highest-priority plugin available", function()
      local config = fresh_config()
      config.set({})
      for j = i, #order do
        package.loaded[order[j][1]] = {}
      end
      assert.equals(pair[2], config.detect_backend())
    end)
  end
end)
