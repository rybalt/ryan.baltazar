-- Disable noice.nvim entirely. LazyVim ships it for the centered cmdline
-- popup, popupmenu styling, message routing, and LSP markdown rendering —
-- we want the classic native cmdline and don't miss the rest. Native nvim
-- handles `vim.notify`, LSP hovers, and signature help adequately.
return {
  { "folke/noice.nvim", enabled = false },
}
