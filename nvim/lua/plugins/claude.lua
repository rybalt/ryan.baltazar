-- Claude Code IDE integration.
--
-- Architecture: Claude Code runs in the iTerm2 hotkey window (NOT in
-- Neovide). claudecode.nvim starts a WebSocket server that Claude Code
-- discovers when launched from a project directory. Diffs and context
-- flow between the two processes over the socket — same protocol as
-- the official JetBrains / VS Code integrations.
--
-- Usage:
--   1. Neovide launches → claudecode.nvim starts the WebSocket server
--      and writes a lockfile to ~/.claude/ide/{port}.lock
--   2. In iTerm2 hotkey: `cd` to the project, run `claude`
--   3. In Claude Code: run `/ide` — it finds the lockfile, connects
--   4. Diffs from CC render in Neovide as diff buffers; hunk-level
--      accept/reject via the keybindings below
return {
  {
    "coder/claudecode.nvim",
    event = "VeryLazy",
    dependencies = { "folke/snacks.nvim" },
    config = true,
    keys = {
      { "<leader>a", nil, desc = "+ai/claude" },

      -- Push context from Neovide to the external Claude Code session
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>",    mode = "v", desc = "Send selection to Claude" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>",              desc = "Add current buffer to context" },

      -- Handle diffs that CC pushes into Neovide
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>",         desc = "Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>",           desc = "Deny diff" },

      -- Status / debugging
      { "<leader>a?", "<cmd>ClaudeCodeStatus<cr>",             desc = "Claude Code status" },
    },
  },
}
