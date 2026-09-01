# sessman.nvim

A Neovim session manager with project-based session organization and tmux-resurrect integration.

**This is a project under development. Please, feel free to open issues or pull request.**

## Features

- Project-based session organization
- Automatic project detection
- Integration with tmux-resurrect
- Multiple backend support (fzf-lua, telescope, mini.pick, snacks)
- Interactive UI buffer for session management

## Installation

<details open>
<summary><strong>Neovim native package manager</strong></summary>

```lua
vim.pack.add({
      'https://github.com/urtzienriquez/sessman.nvim',
      ... ,
})

require("sessman").setup({
  backend = "fzf",  -- or "telescope", "minipick", "snacks", or nil (auto-detect)
})

```

</details> <details> <summary><strong>lazy.nvim</strong></summary>

```lua
{
  "urtzienriquez/sessman.nvim",
  config = function()
    require("sessman").setup({
      backend = "fzf",  -- or "telescope", "minipick", "snacks", or nil (auto-detect)
      session_dir = vim.fn.stdpath("data") .. "/session/",
      project_detection = "auto", -- or "manual"

      keymaps = {
        enabled = true,
        save = "<leader>ms",
        load = "<leader>ml",
        project_pick = "<leader>mp",
        current = "<leader>mc",
        tmux_sync = "<leader>mt",  -- optional: sync with tmux-resurrect
      },
    })
  end,
}
```

</details>

## Configuration

### Default Configuration

```lua
require("sessman").setup({
  -- Picker backend: "fzf", "telescope", "minipick", "snacks", or nil (auto-detect)
  backend = nil,

  -- Session storage directory
  session_dir = vim.fn.stdpath("data") .. "/session/",

  -- Project detection: "auto" sets project to cwd on VimEnter
  project_detection = "auto",

  keymaps = {
    enabled = true,
    save = "<leader>ms",           -- SessionSave
    load = "<leader>ml",           -- SessionLoad
    project_set = false,           -- SessionProjectSet (no default)
    project_pick = "<leader>mp",   -- SessionProjectPick
    project_clear = false,         -- SessionProjectClear (no default)
    current = "<leader>mc",        -- SessionCurrent
    tmux_sync = "<leader>mt",      -- SessionTmuxSync
  },
})
```

### Disable Default Keymaps

```lua
require("sessman").setup({
  keymaps = { enabled = false },
})

-- Set your own keymaps
vim.keymap.set("n", "<leader>s", require("sessman").save)
vim.keymap.set("n", "<leader>l", require("sessman").load)
```

## Usage

### Commands

- `:SessionSave` - Save current session (opens interactive UI)
- `:SessionLoad` - Load a session via picker
- `:SessionProjectSet [path]` - Set project directory
- `:SessionProjectPick` - Pick project directory via picker
- `:SessionProjectClear` - Clear project setting
- `:SessionCurrent` - Open the info window with current session/ShaDa status
- `:SessionInfo` - Toggle the info window (ConformInfo-style status)
- `:SessionTmuxSync` - Sync with tmux-resurrect
- `:SessionDebugStart` / `:SessionDebugStop` - Toggle debug logging

### Status Info Window

`SessionInfo` (or the `current` keymap `<leader>mc`) opens a floating,
ConformInfo-style window showing the current session, ShaDa and project state,
plus a log of recent activity (loaded/saved/deleted sessions, project changes).

Instead of transient echo messages, sessman records session and ShaDa load
events in this window — open it any time to see whether a session is loaded and
which ShaDa file is in use. `q` or `<Esc>` closes it.

### Interactive UI

When you run `:SessionSave`, an interactive buffer opens where you can:

- **`<CR>`** - Toggle options or edit the session name
- **`s`** - Save the session with current settings
- **`q`** - Close the UI
- **`g?`** - Open help documentation
- **`]c` / `[c`** - Jump between configuration sections

The UI allows you to:

- Name your session
- Choose whether to save ShaDa data with the session
- See the current project directory

### Default Keymaps

| Key          | Command            | Description              |
| ------------ | ------------------ | ------------------------ |
| `<leader>ms` | SessionSave        | Save session             |
| `<leader>ml` | SessionLoad        | Load session             |
| `<leader>mp` | SessionProjectPick | Pick project             |
| `<leader>mc` | SessionCurrent     | Open info window         |
| `<leader>mt` | SessionTmuxSync    | Sync with tmux-resurrect |

### API

```lua
local sessman = require("sessman")

sessman.save()            -- Save session
sessman.load()            -- Load session
sessman.project_pick()    -- Pick project
sessman.project_set(path) -- Set project
sessman.current()         -- Open info window
sessman.info()            -- Toggle info window
sessman.tmux_sync()       -- Sync tmux-resurrect
sessman.debug()           -- Show configuration
```

## How It Works

### Session Organization

Sessions are stored in a project-based directory structure:

```
~/.local/share/nvim/session/
├── %home%user%projects%myproject/
│   ├── Session.vim
│   ├── feature-branch.vim
│   └── bugfix.vim
└── %home%user%work%client/
    ├── Session.vim
    └── development.vim
```

Project paths are encoded (using `%` as separator) to create unique session directories.

### Project Detection

- **Auto mode** (default): Sets project to `cwd` on `VimEnter`
- **Manual mode**: Use `:SessionProjectSet` or `:SessionProjectPick`

### Backend Support

sessman automatically detects and uses available picker backends:

- **fzf-lua** - Fast and feature-rich (recommended)
- **telescope** - Popular picker with extensive features
- **mini.pick** - Minimal and lightweight
- **snacks** - Modern picker interface

If no backend is specified in configuration, sessman will auto-detect in this order: fzf-lua → telescope → mini.pick → snacks.

### tmux-resurrect Integration

sessman can sync your Neovim session with tmux-resurrect, so when tmux restores your environment, Neovim automatically loads the correct session.

#### How It Works

When you run `:SessionTmuxSync` (or use the keymap), sessman:

1. **Verifies you're inside tmux** - Shows a warning if not
2. **Checks for an active Neovim session** - You need to save a session first with `:SessionSave`
3. **Finds the tmux-resurrect save file** - Automatically detects both the [original tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) and [my forked version of tmux-resurrect](https://github.com/urtzienriquez/tmux-resurrect).
4. **Updates the resurrect file** - Modifies the pane entry for your current tmux pane to include the Neovim session path

After syncing, when tmux-resurrect restores your environment, the Neovim pane will automatically load with `nvim -S /path/to/your/session.vim`.

#### Compatibility

sessman automatically detects and supports both:

- **Original tmux-resurrect**: Uses a single timestamped file with a `last` symlink
  - Location: `~/.local/share/tmux/resurrect/last` → `tmux_resurrect_TIMESTAMP.txt`
- **My fork of tmux-resurrect**: Uses per-session files in a `saved/` directory
  - Location: `~/.local/share/tmux/resurrect/saved/session_name.resurrect`

The sync command will find the correct file automatically without any configuration needed.

#### Requirements

- You must be running Neovim inside a tmux session
- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) must be installed
- Your tmux session must be saved at least once with tmux-resurrect
- You must have an active Neovim session (saved with `:SessionSave`)

All checks are performed automatically with helpful error messages if something is missing.

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
