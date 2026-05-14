-- Catppuccin (replaces previous Monokai Pro setup). Auto-switches between
-- Latte (light) and Mocha (dark) following Vim's $background, which LazyVim
-- syncs with the macOS system appearance.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "auto",
      background = {
        light = "latte",
        dark = "mocha",
      },
      transparent_background = false,
      term_colors = true,
      styles = {
        comments = { "italic" },
      },
      integrations = {
        cmp = true,
        gitsigns = true,
        nvimtree = true,
        telescope = { enabled = true },
        treesitter = true,
        native_lsp = {
          enabled = true,
          underlines = {
            errors = { "undercurl" },
            hints = { "undercurl" },
            warnings = { "undercurl" },
            information = { "undercurl" },
          },
        },

        -- Lualine integration: catppuccin builds the theme from these
        -- overrides at colorscheme apply time, so we don't need to touch
        -- lualine itself. Goal: keep the mode chevron the only thing that
        -- shifts on mode change, with desaturated bg + mode-colored fg
        -- so the change is legible without sweeping accent paint across
        -- the bar.
        --
        -- Background stays at `surface1` for every mode; only the fg
        -- (and the icon's tint) changes. Section B/C inherit the same
        -- neutral so they stop swinging entirely.
        lualine = {
          all = function(C)
            local neutral_a_bg = C.surface1
            local neutral_b    = { bg = C.surface0, fg = C.subtext1 }
            local neutral_c    = { bg = C.mantle,   fg = C.text }
            return {
              normal   = { a = { bg = neutral_a_bg, fg = C.blue,  gui = "bold" }, b = neutral_b, c = neutral_c },
              insert   = { a = { bg = neutral_a_bg, fg = C.green, gui = "bold" }, b = neutral_b, c = neutral_c },
              terminal = { a = { bg = neutral_a_bg, fg = C.green, gui = "bold" }, b = neutral_b, c = neutral_c },
              visual   = { a = { bg = neutral_a_bg, fg = C.mauve, gui = "bold" }, b = neutral_b, c = neutral_c },
              command  = { a = { bg = neutral_a_bg, fg = C.peach, gui = "bold" }, b = neutral_b, c = neutral_c },
              replace  = { a = { bg = neutral_a_bg, fg = C.red,   gui = "bold" }, b = neutral_b, c = neutral_c },
              inactive = {
                a = { bg = C.mantle, fg = C.overlay0 },
                b = { bg = C.mantle, fg = C.overlay0 },
                c = { bg = C.mantle, fg = C.overlay0 },
              },
            }
          end,
        },
      },

      -- Latte's default cursor is text-colored on the base background —
      -- technically max text-vs-bg contrast, but visually muted because
      -- both ends sit in the neutral gray range. Swap to mauve (the same
      -- accent we keep for the active tmux window slot) so the cursor
      -- pops out of the page instead of blending into the prose.
      --
      -- C is the flavor's palette: https://github.com/catppuccin/catppuccin#-palette
      highlight_overrides = {
        latte = function(C)
          return {
            Cursor = { bg = C.mauve, fg = C.base },
          }
        end,
      },
    },
  },

  -- Tell LazyVim to use it
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
