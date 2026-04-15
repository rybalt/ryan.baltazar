-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- Prose prettification for markdown/text buffers (replaces rb-prose-mode
-- from Emacs: visual-line-mode + disabled line numbers).
-- Font swap (iA Writer Quattro for prose) is a separate follow-up.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "text" },
  callback = function()
    vim.opt_local.wrap            = true
    vim.opt_local.linebreak       = true
    vim.opt_local.breakindent     = true
    vim.opt_local.number          = false
    vim.opt_local.relativenumber  = false
  end,
})

-- Note on heading sizes: Neovim (and Neovide) don't support per-highlight
-- font sizes, so org-style H1>H2>H3 scaling isn't achievable. Differentiation
-- is via bold weight, icons, and per-level colors/backgrounds (see
-- lua/plugins/markdown.lua render-markdown opts).

-- Register custom rb.* modules.
require("rb.homepage").setup()
