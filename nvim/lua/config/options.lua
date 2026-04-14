-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Keep CWD stable so workspace-root detection works reliably (see rb/workspace.lua)
vim.opt.autochdir = false

-- Neovide (GUI) configuration
if vim.g.neovide then
  vim.opt.guifont = "FiraMono Nerd Font:h14"

  vim.g.neovide_padding_top    = 12
  vim.g.neovide_padding_bottom = 12
  vim.g.neovide_padding_left   = 12
  vim.g.neovide_padding_right  = 12

  -- Cursor animation off (too distracting)
  vim.g.neovide_cursor_animation_length       = 0
  vim.g.neovide_cursor_trail_size             = 0
  vim.g.neovide_cursor_animate_in_insert_mode = false
  vim.g.neovide_cursor_animate_command_line   = false

  -- Smooth scrolling — keep
  vim.g.neovide_scroll_animation_length = 0.1

  -- Floating-window blur (popups only — main window stays opaque).
  -- winblend/pumblend make floating windows pseudo-transparent; Neovide
  -- then applies a real backdrop blur behind them.
  vim.g.neovide_floating_blur_amount_x = 2.0
  vim.g.neovide_floating_blur_amount_y = 2.0
  vim.g.neovide_floating_shadow        = true
  vim.g.neovide_floating_corner_radius = 0.5
end

-- Pseudo-transparency for floating windows and the completion popup menu.
-- Values 0–100 (higher = more transparent). Set outside the Neovide block
-- so the options are in effect if the config is ever used in terminal nvim.
vim.opt.winblend  = 10
vim.opt.pumblend  = 10
