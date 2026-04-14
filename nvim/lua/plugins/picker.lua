-- Picker layout: top-center floating frame (matches vertico-posframe from Emacs)
-- LazyVim uses snacks.picker by default.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- "dropdown" is snacks' built-in top-anchored float preset.
        -- If it's not close enough to the Emacs vertico-posframe feel,
        -- we can define a custom layout here instead.
        layout = {
          preset = "dropdown",
        },
      },
    },
  },
}
