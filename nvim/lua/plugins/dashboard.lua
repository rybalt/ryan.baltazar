-- Disable LazyVim's startup dashboard (snacks.dashboard). With it off,
-- `nvim` with no args opens an empty buffer and `nvim .` falls through to
-- neo-tree's directory view (neo-tree hijacks netrw by default).
return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = { enabled = false },
    },
  },
}
