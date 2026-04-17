-- snacks.picker configuration.
-- - layout: top-center floating frame (matches vertico-posframe from Emacs)
-- - files source: include dotted dirs (.github, .claude, agent docs, etc.)
--   while still respecting .gitignore (Unity Library/ etc. stay hidden).
--   .git itself is excluded explicitly since we don't want git internals.
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
  },
}
