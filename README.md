# sessman.nvim

Named Neovim sessions that keep **running** (survive closing the terminal) or stay **saved** (survive reboots).

**This is a project under development. Please, feel free to open issues or pull requests.**

One command, like fugitive's `:Git` (`:S` for short, like `:G`):

- `:Session` — list every session, grouped by project (fugitive-style buffer, `g?` for maps)
- `:Session switch coding` — jump to it if running, restore it if saved; `:Session switch -` goes back
- `:Session new ~/papers/thesis:writing` — a new session `writing` in the project `~/papers/thesis` (`project:name`, like fugitive's `HEAD:file`)
- `:Session save` — save the current session; `:Session save notes` turns a plain nvim into a session
- `:Session kill [name]`, `:Session delete name` — stop a session / remove it

A session belongs to a project (the git root, or a directory) or is global, and keeps its own working directory. Saving is always explicit. Nothing but two commands is defined at startup. See `:help sessman`.

Requires Neovim 0.12+ on a Unix-like system.

## Installation

```lua
vim.pack.add({ "https://github.com/urtzienriquez/sessman.nvim" })
```

No `setup()` needed. Optional:

```lua
vim.g.sessman_dir = vim.fn.expand("~/sessions") -- default: stdpath("data") .. "/session"
vim.keymap.set("n", "<leader>ss", "<Cmd>Session<CR>", { desc = "Session list" })
vim.keymap.set("n", "<leader>sp", "<Cmd>Session switch -<CR>", { desc = "Previous session" })
vim.keymap.set("n", "<leader>sl", function() require("sessman").pick() end, { desc = "Pick a session" })
```

## Credits

The live-server half is adapted from [servery.nvim](https://github.com/wurli/servery.nvim) (MIT).

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
