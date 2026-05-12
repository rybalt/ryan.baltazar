return {
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>",  desc = "Navigate left (tmux)"  },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>",  desc = "Navigate down (tmux)"  },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>",    desc = "Navigate up (tmux)"    },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate right (tmux)" },
    },
  },
}
