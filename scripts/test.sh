#!/usr/bin/env bash
# Runs the plenary.nvim test suite. Clones plenary into tests/deps/ on first
# run (gitignored, dev-only). Requires: nvim, git.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deps_dir="$root/tests/deps"
plenary_dir="$deps_dir/plenary.nvim"

if [ ! -d "$plenary_dir" ]; then
  echo "Cloning plenary.nvim into $plenary_dir ..."
  mkdir -p "$deps_dir"
  git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$plenary_dir"
fi

target="${1:-$root/tests/sessman}"

nvim --headless --noplugin \
  -u "$root/tests/minimal_init.lua" \
  -c "PlenaryBustedDirectory $target { minimal_init = '$root/tests/minimal_init.lua', sequential = true }"
