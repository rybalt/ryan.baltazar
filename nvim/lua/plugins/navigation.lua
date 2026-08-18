-- Seamless split navigation across nvim + terminal multiplexer. Replaces
-- vim-tmux-navigator. smart-splits auto-detects the multiplexer (tmux today,
-- WezTerm after the migration) and hands off at the split edge, so C-hjkl
-- crosses between nvim splits and multiplexer panes transparently — no
-- multiplexer-specific config here (the WezTerm side gets wired in Diff 3).
return {
  {
    "mrjones2014/smart-splits.nvim",
    -- Not lazy-loaded: the WezTerm handoff (wezterm/wezterm.lua) reads the
    -- IS_NVIM user var that smart-splits emits on load, so it must be up from
    -- startup, not deferred to the first keypress.
    lazy = false,
    opts = {
      -- Pin the multiplexer explicitly instead of trusting auto-detection, so
      -- the WezTerm-specific behavior (emitting the IS_NVIM OSC, shelling to
      -- `wezterm cli` at the split edge) fires *iff* WezTerm is the DIRECT
      -- terminal. $TMUX is checked first: nvim inside tmux — including
      -- tmux-inside-WezTerm, where $WEZTERM_PANE is still inherited — resolves
      -- to tmux, never wezterm. That matters because tmux swallows the IS_NVIM
      -- OSC and the wezterm-CLI edge handoff wouldn't apply through a tmux
      -- layer (the existing tmux is_vim bindings cover that case). Anything
      -- else (bare terminal, kitty, zellij) falls back to auto-detect.
      multiplexer_integration = (function()
        if vim.env.TMUX then return "tmux" end
        if vim.env.WEZTERM_PANE then return "wezterm" end
        return nil
      end)(),
    },
    keys = {
      { "<C-h>", function() require("smart-splits").move_cursor_left() end,  desc = "Move to left split"  },
      { "<C-j>", function() require("smart-splits").move_cursor_down() end,  desc = "Move to below split" },
      { "<C-k>", function() require("smart-splits").move_cursor_up() end,    desc = "Move to above split" },
      { "<C-l>", function() require("smart-splits").move_cursor_right() end, desc = "Move to right split" },
    },
  },
}
