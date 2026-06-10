-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Prose prettification for markdown/text buffers (replaces rb-prose-mode
-- from Emacs: visual-line-mode + disabled line numbers).
-- Font swap (iA Writer Quattro for prose) is a separate follow-up.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text" },
  callback = function(ev)
    local is_md = ev.match == "markdown"
    -- markdown: wrap OFF. render-markdown.nvim draws table borders as
    -- virtual text per screen-line; soft-wrapped rows get no border and
    -- shatter the grid. Prose is instead hard-wrapped at 120 in the source
    -- by conform/prettier (see plugins/markdown.lua). Wide tables overflow
    -- right -> horizontal scroll.
    -- text: keep soft-wrap (no table rendering, no source formatter).
    vim.opt_local.wrap            = not is_md
    vim.opt_local.linebreak       = not is_md
    vim.opt_local.breakindent     = not is_md
    vim.opt_local.number          = false
    vim.opt_local.relativenumber  = false
    if is_md then
      vim.opt_local.sidescroll    = 1 -- scroll 1 col at a time, not half-screen
      vim.opt_local.sidescrolloff = 8 -- keep 8 cols of context past the cursor
    end
  end,
})

-- Note on heading sizes: Neovim (and Neovide) don't support per-highlight
-- font sizes, so org-style H1>H2>H3 scaling isn't achievable. Differentiation
-- is via bold weight, icons, and per-level colors/backgrounds (see
-- lua/plugins/markdown.lua render-markdown opts).

-- Register custom rb.* modules.
require("rb.homepage").setup()
