-- Follow the OS appearance setting (macOS / Linux / Windows). auto-dark-mode
-- polls the platform's native theme indicator on a timer and calls the
-- set_dark_mode / set_light_mode callbacks when it changes.
--
-- We only need to flip `vim.o.background` — catppuccin already listens for
-- OptionSet on `background` and recompiles to the matching flavor (latte
-- for light, mocha for dark, per colorscheme.lua).
return {
  {
    "f-person/auto-dark-mode.nvim",
    lazy = false,
    priority = 900, -- after catppuccin (1000), before lualine et al.
    opts = {
      update_interval = 3000, -- ms between OS appearance polls
      set_dark_mode   = function() vim.o.background = "dark"  end,
      set_light_mode  = function() vim.o.background = "light" end,
    },
  },
}
