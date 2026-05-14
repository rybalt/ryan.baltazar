-- Disable LazyVim defaults that don't match this config's "classic, no
-- decorative popups" preference. Reasons captured here so future-me
-- remembers what's deliberate vs. drift.
return {
  -- Buffer tabs across the top. Redundant with tmux windows, and competes
  -- with the tmux statusline (also pinned to the top) for visual real estate.
  { "akinsho/bufferline.nvim", enabled = false },

  -- Auto-closes brackets/quotes/parens as you type. "Predictable > magic"
  -- preference: avoid the editor making structural edits without an explicit
  -- keystroke.
  { "nvim-mini/mini.pairs", enabled = false },

  -- Auto session save/restore. Not currently used; tmux already provides
  -- per-window persistence at the shell level.
  { "folke/persistence.nvim", enabled = false },

  -- LazyVim's default colorscheme. Catppuccin is wired up in colorscheme.lua,
  -- tokyonight never gets picked — pure dead weight on startup.
  { "folke/tokyonight.nvim", enabled = false },

  -- Trim the snacks.nvim megamodule down to just the parts we use
  -- (picker, explorer, indent guides, bigfile, quickfile, statuscolumn).
  -- Everything below is decoration or popup-style UX that doesn't fit
  -- the classic feel.
  {
    "folke/snacks.nvim",
    opts = {
      -- Centered popup replacing vim.ui.input (LSP rename, etc.). Same
      -- magic-popup family we turned off for the cmdline.
      input    = { enabled = false },
      -- Smooth-scroll animation on <C-d>/<C-u>. Pure decoration.
      scroll   = { enabled = false },
      -- Fancy toast notifications. Native :messages / vim.notify is fine.
      notifier = { enabled = false },
      -- Auto-highlights other occurrences of the word under cursor on
      -- every CursorMoved. Background work + visual chatter.
      words    = { enabled = false },
      -- Animation primitives — only needed by the modules above.
      animate  = { enabled = false },
    },
  },
}
