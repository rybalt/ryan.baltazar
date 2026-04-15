-- noice.nvim tweaks: stop routing transient messages (":3 fewer lines",
-- "search hit bottom", etc.) into floating popups. Send them back to
-- the classic cmdline area at the bottom of the screen, like plain Neovim.
-- Other noice features (fancy cmdline input, LSP progress) stay intact.
return {
  {
    "folke/noice.nvim",
    opts = {
      messages = {
        enabled = false,
      },
      notify = {
        -- Also keep transient notifications out of popups (nvim-notify's
        -- toasts can feel intrusive for terse edit feedback).
        enabled = false,
      },
    },
  },
}
