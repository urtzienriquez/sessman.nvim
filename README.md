# sessman.nvim

Named Neovim sessions that keep **running** (survive closing the terminal) or
stay **saved** (survive reboots) — tmux + tmux-resurrect, made of Nvim's own
client/server parts.

**This is a project under development. Please, feel free to open issues or pull requests.**

- `:Session` — list every session, grouped by project (fugitive-style buffer,
  `g?` for maps)
- `:Session coding` — jump to it if running, restore it if saved, create it
  otherwise
- `:Session -` — back to the previous session
- `:SessionSave` — save the current session; `:SessionSave notes` turns a
  plain nvim into a session

A session belongs to a project (the git root, or a directory) or is global,
and keeps its own working directory. Saving is always explicit. Nothing but
two commands is loaded at startup. See `:help sessman`.

Requires Neovim 0.12+ on a Unix-like system.

## Installation

```lua
vim.pack.add({ "https://github.com/urtzienriquez/sessman.nvim" })
```

No `setup()` needed. Optional:

```lua
vim.g.sessman_dir = vim.fn.expand("~/sessions") -- default: stdpath("data") .. "/session"
vim.keymap.set("n", "<leader>s", "<Cmd>Session<CR>")
vim.keymap.set("n", "<leader>S", "<Cmd>Session -<CR>")
```

## Credits

The live-server half is adapted from
[servery.nvim](https://github.com/wurli/servery.nvim) (MIT).

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
