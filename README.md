# sessman.nvim

A project-based session manager for Neovim, with tmux-resurrect integration.

**This is a project under development. Please, feel free to open issues or pull requests.**

Sessions are organized by project directory, with an optional ShaDa file per
session. `:SessionLoad` opens a persistent session-list buffer for the
current project — press `g?` there for every mapping (load, delete, save,
project management, navigation). No keymaps are set for you; bind whatever
you like, e.g.:

```lua
vim.keymap.set("n", "<leader>ms", "<Cmd>SessionLoad<CR>")
```

For everything else — commands, the API, the session-list/UI/info buffers,
project detection, tmux-resurrect — see `:help sessman`.

## Installation

<details open>
<summary><strong>Neovim native package manager</strong></summary>

```lua
vim.pack.add({
  "https://github.com/urtzienriquez/sessman.nvim",
})

require("sessman").setup()
```

</details>
<details>
<summary><strong>lazy.nvim</strong></summary>

```lua
{
  "urtzienriquez/sessman.nvim",
  config = function()
    require("sessman").setup()
    vim.keymap.set("n", "<leader>ms", "<Cmd>SessionLoad<CR>")
  end,
}
```

</details>

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
