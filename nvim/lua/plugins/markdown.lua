-- Markdown prettification stack (replaces rb-prose-mode from Emacs:
-- olivetti-mode + visual-line-mode + org-modern glyphs + scaled headings).
return {
  -- Inline markdown rendering — headings, lists, code blocks, checkboxes.
  -- Un-renders on cursor entry for editing (analogous to org-appear).
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-mini/mini.icons",
    },
    opts = {
      -- Render in every mode EXCEPT insert. Entering insert reveals the
      -- raw markdown buffer-wide (like org-appear-trigger 'manual + evil
      -- insert-state hooks from Emacs); exiting re-renders. Normal-mode
      -- navigation stays fully rendered with no per-line pop-in.
      render_modes = { "n", "c", "t", "v", "V", "\22" }, -- \22 = CTRL-V

      -- Re-render quickly; default 100ms produces visible lag on scroll.
      debounce = 10,

      -- Disable anti-conceal entirely — insert-mode toggle does the job.
      anti_conceal = { enabled = false },

      heading = {
        enabled = false, -- show raw #, ##, ### markers; treesitter handles styling
      },
      code = {
        sign = false,
        width = "block",    -- highlight extends only to longest code line
        left_pad = 2,
        right_pad = 2,
      },
      bullet = {
        -- Match rb-prose from Emacs: • ◦ ▸
        icons = { "●", "◦", "▸", "▹" },
      },
      checkbox = {
        unchecked = { icon = "☐" },
        checked   = { icon = "☑" },
      },
    },
  },

  -- Markdown formatting: hard-wrap prose at 120 in the source so buffers can
  -- run with wrap=false (keeps render-markdown table borders aligned, see
  -- config/autocmds.lua). prettier wraps prose to print-width but never wraps
  -- table cells.
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        markdown = { "prettier" },
      },
      formatters = {
        prettier = {
          prepend_args = { "--print-width", "120", "--prose-wrap", "always" },
        },
      },
    },
  },
  -- Ensure the prettier binary is installed.
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "prettier" } },
  },

  -- Focused reading/writing view (replaces olivetti-mode from Emacs).
  -- zen-mode hides sibling windows (explorer, splits) and centers the
  -- current buffer at a fixed width. Toggle on/off to switch between
  -- normal layout and focused view.
  {
    "folke/zen-mode.nvim",
    cmd = "ZenMode",
    keys = {
      { "<leader>uz", "<cmd>ZenMode<cr>", desc = "Toggle zen mode" },
    },
    opts = {
      window = {
        backdrop = 1,       -- no screen dimming (keep 100% opacity)
        width = 120,        -- absolute columns; matches request
        height = 1,         -- full-height
        options = {
          number = false,
          relativenumber = false,
          signcolumn = "no",
          cursorline = false,
          foldcolumn = "0",
        },
      },
      plugins = {
        options = {
          ruler = false,
          showcmd = false,
          laststatus = 0,
        },
        gitsigns = { enabled = false }, -- hide hunk indicators in zen
        tmux = { enabled = false },
      },
    },
  },
}
