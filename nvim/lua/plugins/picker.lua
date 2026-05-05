-- snacks.picker configuration.
-- - layout: top-center floating frame (matches vertico-posframe from Emacs)
-- - files source: include dotted dirs (.github, .claude, agent docs, etc.)
--   while still respecting .gitignore (Unity Library/ etc. stay hidden).
--   .git itself is excluded explicitly since we don't want git internals.
-- - <leader><space> and <leader>e are re-bound to use vim.fn.getcwd() instead
--   of the git root of the current buffer, so they scope to the umbrella
--   workspace root when Neovide is launched from there.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        layout = {
          preset = "dropdown",
        },
        sources = {
          files = {
            hidden  = true,                      -- --hidden: include dotted paths
            follow  = true,                      -- -L: follow symlinks (docs/ → planning/)
            exclude = { ".git", ".vscode" },     -- but not git internals or per-user editor config
            -- ignored stays default (respect .gitignore): build artifacts
            -- and anything an explicit .gitignore / .fdignore hides stays hidden.
          },
        },
      },
    },
    keys = {
      -- Override LazyVim's "root dir" (git root) variants with explicit cwd.
      -- vim.fn.getcwd() is evaluated at call time, so it always reflects
      -- wherever Neovide was launched from (typically the umbrella root).
      {
        "<leader><space>",
        function() Snacks.picker.files({ cwd = vim.fn.getcwd() }) end,
        desc = "Find Files (cwd)",
      },
      {
        "<leader>e",
        function() Snacks.explorer({ cwd = vim.fn.getcwd() }) end,
        desc = "Explorer (cwd)",
      },
      {
        "<leader>E",
        function() Snacks.explorer({ cwd = vim.fn.getcwd() }) end,
        desc = "Explorer (cwd)",
      },
    },
  },
}
