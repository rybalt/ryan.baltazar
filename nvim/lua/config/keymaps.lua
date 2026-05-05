-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Scrollwheel scrolls the viewport only; cursor (and visual selection) stays put.
-- Neovim's default maps ScrollWheel to cursor movement, which in visual mode
-- extends/contracts the selection unexpectedly — very surprising on macOS.
-- <C-y>/<C-e> scroll one line at a time without touching the cursor.
-- Insert mode uses <C-O> to run a single normal command then return.
vim.keymap.set({ "n", "v" }, "<ScrollWheelUp>",   "<C-Y>",           { silent = true })
vim.keymap.set({ "n", "v" }, "<ScrollWheelDown>", "<C-E>",           { silent = true })
vim.keymap.set("i",          "<ScrollWheelUp>",   "<C-O><C-Y>",      { silent = true })
vim.keymap.set("i",          "<ScrollWheelDown>", "<C-O><C-E>",      { silent = true })

-- macOS-native Cmd shortcuts (requires vim.g.neovide_input_use_logo = 1 from options.lua).
-- The <D-...> key code is Neovim's notation for the logo/Cmd modifier.
if vim.g.neovide then
  -- Paste from system clipboard
  vim.keymap.set({ "n", "v" }, "<D-v>", '"+p',    { desc = "Paste (clipboard)" })
  vim.keymap.set({ "c", "i" }, "<D-v>", "<C-r>+", { desc = "Paste (clipboard)" })
  vim.keymap.set("t",          "<D-v>", [[<C-\><C-n>"+pi]], { desc = "Paste (clipboard)" })

  -- Copy to system clipboard (redundant with clipboard=unnamedplus but feels native)
  vim.keymap.set("v", "<D-c>", '"+y', { desc = "Copy (clipboard)" })

  -- Save
  vim.keymap.set({ "n", "v", "i" }, "<D-s>", "<cmd>w<cr>", { desc = "Save" })

  -- Select-all (normal mode only — visual would be redundant)
  vim.keymap.set("n", "<D-a>", "ggVG", { desc = "Select all" })
end
