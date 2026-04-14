-- Monokai Pro (replacement for doom-monokai-pro from Emacs)
return {
  {
    "loctvl842/monokai-pro.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent_background = false,
      terminal_colors = true,
      devicons = true,
      styles = {
        comment = { italic = true },
      },
      -- Filter: classic | octagon | pro | machine | ristretto | spectrum.
      -- "pro" matches doom-monokai-pro from the Emacs config.
      filter = "pro",
    },
  },

  -- Tell LazyVim to use it
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "monokai-pro",
    },
  },
}
