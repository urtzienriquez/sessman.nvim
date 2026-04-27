# sessman.nvim

A Neovim session manager with project-based session organization and tmux-resurrect integration.

## Features

- Project-based session organization
- Automatic project detection
- Integration with tmux-resurrect
- Fuzzy session picker (fzf-lua)
- Configurable keymaps and behavior

## Installation

### lazy.nvim

```lua
{
  "urtzienriquez/sessman.nvim",
  dependencies = {
    "ibhagwan/fzf-lua",
  },
  config = function()
    require("sessman").setup({
      session_dir = vim.fn.stdpath("data") .. "/session/",
      project_detection = "auto", -- or "manual"
      tmux_integration = true,
      
      keymaps = {
        enabled = true,
        save = "<leader>ss",
        load = "<leader>sl",
        project_pick = "<leader>sp",
        current = "<leader>sc",
      },
    })
  end,
}
```

## Configuration

### Default Configuration

```lua
require("sessman").setup({
  -- Session storage directory
  session_dir = vim.fn.stdpath("data") .. "/session/",
  
  -- Project detection: "auto" sets project to cwd on VimEnter
  project_detection = "auto",
  
  -- Enable tmux-resurrect integration
  tmux_integration = true,
  
  keymaps = {
    enabled = true,
    save = "<leader>ms",           -- SessionSave
    load = "<leader>ml",           -- SessionLoad
    project_set = false,           -- SessionProjectSet (no default)
    project_pick = "<leader>mp",   -- SessionProjectPick
    project_clear = false,         -- SessionProjectClear (no default)
    current = "<leader>mc",        -- SessionCurrent
    tmux_sync = false,             -- SessionTmuxSync (no default)
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

- `:SessionSave` - Save current session (opens UI to name it)
- `:SessionLoad` - Load a session via picker
- `:SessionProjectSet [path]` - Set project directory
- `:SessionProjectPick` - Pick project directory via picker
- `:SessionProjectClear` - Clear project setting
- `:SessionCurrent` - Show current session file path
- `:SessionTmuxSync` - Sync with tmux-resurrect
- `:SessionDebugStart` / `:SessionDebugStop` - Toggle debug logging

### Default Keymaps

| Key | Command | Description |
|-----|---------|-------------|
| `<leader>ss` | SessionSave | Save session |
| `<leader>sl` | SessionLoad | Load session |
| `<leader>sp` | SessionProjectPick | Pick project |
| `<leader>sc` | SessionCurrent | Show current session |

### API

```lua
local sessman = require("sessman")

sessman.save()           -- Save session
sessman.load()           -- Load session
sessman.project_pick()   -- Pick project
sessman.project_set(path) -- Set project
sessman.current()        -- Show current session
sessman.tmux_sync()      -- Sync tmux-resurrect
sessman.debug()          -- Show configuration
```

## How It Works

### Session Organization

Sessions are stored in a project-based directory structure:

```
~/.local/share/nvim/session/
├── home%user%projects%myproject/
│   ├── Session.vim
│   ├── feature-branch.vim
│   └── bugfix.vim
└── home%user%work%client/
    ├── Session.vim
    └── development.vim
```

Project paths are encoded (using `%` as separator) to create unique session directories.

### Project Detection

- **Auto mode** (default): Sets project to `cwd` on `VimEnter`
- **Manual mode**: Use `:SessionProjectSet` or `:SessionProjectPick`

### tmux-resurrect Integration

When `tmux_integration = true`, sessman automatically updates your tmux-resurrect session file to restore Neovim with the correct session when tmux restores.

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
