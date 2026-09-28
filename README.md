# sessman.nvim

sessman lets you move between Neovim [servers](https://neovim.io/doc/user/remote.html) and restore them from [session files](https://neovim.io/doc/user/starting.html#session-file). It names each session (a `:mksession` file) and connects you to the Nvim server that has it; when no server has it, for example after a reboot, it starts one from the session file.

**This is a project under development. Please, feel free to open issues or pull requests.**

One command, like fugitive's `:Git` (`:S` for short, like `:G`):

- `:Session` — list servers and sessions (fugitive-style buffer, `g?` for maps)
- `:Session connect coding` — `:connect` to the server that has session `coding`; `:Session connect -` goes back; `:Session connect` picks a server
- `:Session load review` — start a server that loads session `review`; `:Session load` picks a session
- `:Session new ~/papers/thesis:writing` — a server with a new session `writing` in the project `~/papers/thesis` (`project:name`, like fugitive's `HEAD:file`)
- `:Session save` — write this server's session file; `:Session save notes` gives a plain nvim a session
- `:Session stop [name]`, `:%Session stop`, `:Session delete name` — stop a server / all others / delete a session

A session belongs to a project (found like LSP's `root_markers`, by default the git root) or is global, and keeps its own working directory. Saving is always explicit. Nothing but two commands is defined at startup. See `:help sessman`.

Requires Neovim 0.12+ on a Unix-like system.

## Installation

```lua
vim.pack.add({ "https://github.com/urtzienriquez/sessman.nvim" })
```

No `setup()` needed. Optional:

```lua
vim.g.sessman_dir = vim.fn.expand("~/sessions") -- default: stdpath("data") .. "/session"
vim.g.sessman_root_markers = { ".git", "DESCRIPTION" } -- default: { ".git" }
vim.g.sessman_exclude = { "R-console" } -- buffers never written into session files (e.g. REPL consoles)
vim.keymap.set("n", "<leader>ss", "<Cmd>Session<CR>", { desc = "Sessions and servers" })
vim.keymap.set("n", "<leader>sc", "<Cmd>Session connect<CR>", { desc = "Connect to a server" })
vim.keymap.set("n", "<leader>sl", "<Cmd>Session load<CR>", { desc = "Load a session" })
vim.keymap.set("n", "<leader>sw", "<Cmd>Session save<CR>", { desc = "Write session" })
vim.keymap.set("n", "<leader>s-", "<Cmd>Session connect -<CR>", { desc = "Previous server" })
```

## Credits

The server half is adapted from [servery.nvim](https://github.com/wurli/servery.nvim) (MIT).

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
