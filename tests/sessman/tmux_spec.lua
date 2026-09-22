local env = require("tests.helpers.env")

--- Build a tmux-resurrect "pane" line (11 tab-separated fields).
local function pane(session, window, command, full)
  return table.concat({ "pane", session, tostring(window), "1", ":*", "0", ":bash", ":/tmp", "1", command, full }, "\t")
end

describe("tmux", function()
  local tmux, resurrect, notes, orig_tmux

  before_each(function()
    env.setup()
    env.fresh("sessman.info")
    tmux = env.fresh("sessman.tmux")
    orig_tmux = vim.env.TMUX
    vim.env.TMUX = "/tmp/tmux-fake,1,0"
    resurrect = env.root .. "/resurrect"
    vim.fn.mkdir(resurrect, "p")
    vim.env.FAKE_RESURRECT_DIR = resurrect
    vim.env.FAKE_TMUX_SESSION = "main"
    vim.env.FAKE_TMUX_WINDOW = "2"
    vim.env.FAKE_TMUX_PANE = "1"
    env.fake_bin(
      "tmux",
      [[
case "$1" in
  show-option) echo "$FAKE_RESURRECT_DIR" ;;
  display-message)
    case "$3" in
      '#{session_name}') echo "$FAKE_TMUX_SESSION" ;;
      '#{window_index}') echo "$FAKE_TMUX_WINDOW" ;;
      '#{pane_index}') echo "$FAKE_TMUX_PANE" ;;
    esac ;;
  *) exit 1 ;;
esac]]
    )
    notes = env.capture_notify()
    vim.v.this_session = env.write_session("work.vim")
  end)

  after_each(function()
    vim.env.TMUX = orig_tmux
    env.teardown()
  end)

  local function expected_cmd()
    return ":nvim -S '" .. vim.v.this_session:gsub("%%", "\\%%") .. "'"
  end

  describe("is_inside_tmux()", function()
    it("is true when $TMUX is set", function()
      assert.is_true(tmux.is_inside_tmux())
    end)

    it("is false when $TMUX is unset or empty", function()
      vim.env.TMUX = ""
      assert.is_false(tmux.is_inside_tmux())
      vim.env.TMUX = nil
      assert.is_false(tmux.is_inside_tmux())
    end)
  end)

  describe("update_tmux_resurrect_session()", function()
    it("warns when not inside tmux", function()
      vim.env.TMUX = nil
      tmux.update_tmux_resurrect_session()
      assert.is_true(env.notified(notes, "Not running inside a tmux session", vim.log.levels.WARN))
    end)

    it("warns when no Neovim session is active", function()
      vim.v.this_session = ""
      vim.fn.writefile({ "" }, resurrect .. "/last")
      tmux.update_tmux_resurrect_session()
      assert.is_true(env.notified(notes, "No active Neovim session", vim.log.levels.WARN))
    end)

    it("warns when there is no resurrect save file", function()
      tmux.update_tmux_resurrect_session()
      assert.is_true(env.notified(notes, "No tmux-resurrect save file found", vim.log.levels.WARN))
    end)

    it("does nothing when tmux cannot report the session", function()
      vim.env.FAKE_TMUX_WINDOW = "not-a-number"
      vim.fn.writefile({ pane("main", 2, "nvim", ":nvim") }, resurrect .. "/last")
      tmux.update_tmux_resurrect_session()
      assert.same({ pane("main", 2, "nvim", ":nvim") }, vim.fn.readfile(resurrect .. "/last"))
      assert.equals(0, #notes)
    end)

    describe("original layout ('last' symlink)", function()
      local save_file

      before_each(function()
        save_file = resurrect .. "/tmux_resurrect_20260101.txt"
        vim.uv.fs_symlink(save_file, resurrect .. "/last")
      end)

      it("rewrites the nvim pane of the current window to restore the session", function()
        vim.fn.writefile({
          "window\tmain\t2\t:bash\t1\t:*\tlayout\t:",
          pane("main", 1, "nvim", ":nvim"),
          pane("main", 2, "bash", ":"),
          pane("other", 2, "nvim", ":nvim"),
          pane("main", 2, "nvim", ":nvim"),
        }, save_file)
        tmux.update_tmux_resurrect_session()
        local lines = vim.fn.readfile(save_file)
        assert.equals(pane("main", 1, "nvim", ":nvim"), lines[2])
        assert.equals(pane("main", 2, "bash", ":"), lines[3])
        assert.equals(pane("other", 2, "nvim", ":nvim"), lines[4])
        assert.equals(pane("main", 2, "nvim", expected_cmd()), lines[5])
        assert.equals(0, #notes)
      end)

      it("escapes % in the session path", function()
        vim.fn.writefile({ pane("main", 2, "nvim", ":nvim") }, save_file)
        tmux.update_tmux_resurrect_session()
        local field = vim.split(vim.fn.readfile(save_file)[1], "\t")[11]
        assert.truthy(field:find("\\%", 1, true))
        assert.falsy(field:find("[^\\]%%"))
      end)

      it("warns when no pane matches", function()
        vim.fn.writefile({ pane("main", 1, "nvim", ":nvim"), "pane\tshort\tline" }, save_file)
        tmux.update_tmux_resurrect_session()
        assert.is_true(env.notified(notes, "No matching pane found", vim.log.levels.WARN))
        assert.equals(pane("main", 1, "nvim", ":nvim"), vim.fn.readfile(save_file)[1])
      end)
    end)

    describe("fork layout (saved/<session>.resurrect)", function()
      before_each(function()
        vim.fn.mkdir(resurrect .. "/saved", "p")
      end)

      it("warns when the tmux session has not been saved", function()
        tmux.update_tmux_resurrect_session()
        assert.is_true(env.notified(notes, "has not been saved by tmux-resurrect", vim.log.levels.WARN))
      end)

      it("rewrites the per-session save file", function()
        local file = resurrect .. "/saved/main.resurrect"
        vim.fn.writefile({ pane("main", 2, "nvim", ":nvim") }, file)
        tmux.update_tmux_resurrect_session()
        assert.equals(pane("main", 2, "nvim", expected_cmd()), vim.fn.readfile(file)[1])
      end)
    end)
  end)
end)
