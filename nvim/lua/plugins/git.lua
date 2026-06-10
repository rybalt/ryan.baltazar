-- Git integration stack.
--
-- - Neogit: Magit-shaped UI (status, stage hunks, commit, branch, log)
-- - gitlinker.nvim: copy GitHub permalinks (replaces rb-github-link.el)
-- - gitsigns.nvim: inline hunk indicators + ]h/[h navigation (already
--   included by LazyVim defaults; no spec needed here)
--
-- Multi-repo picker (SPC gg pick-a-repo over the umbrella's sub-repos)
-- lands as a follow-up. For now Neogit operates on the BUFFER's nearest
-- git repo (not the editor's CWD, which is typically the umbrella root
-- with no .git of its own). See buffer_repo_root() below.

-- Resolve the git repo containing the current buffer, walking up from the
-- buffer's path (not from CWD — the umbrella root has no .git).
local function buffer_repo_root()
  local buf_path = vim.fn.expand("%:p")
  local start = (buf_path ~= "" and vim.fn.fnamemodify(buf_path, ":h")) or vim.fn.getcwd()
  local git = vim.fs.find(".git", { path = start, upward = true })[1]
  return git and vim.fs.dirname(git) or nil
end

local function neogit_for_buffer(action)
  local root = buffer_repo_root()
  if not root then
    vim.notify("Not in a git repo", vim.log.levels.WARN)
    return
  end
  if action then
    vim.cmd(string.format("Neogit cwd=%s %s", vim.fn.fnameescape(root), action))
  else
    require("neogit").open({ cwd = root })
  end
end

return {
  -- Magit-shaped git porcelain
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    keys = {
      { "<leader>gg", function() neogit_for_buffer() end,         desc = "Neogit status (buffer's repo)" },
      { "<leader>gL", function() neogit_for_buffer("log") end,    desc = "Neogit log" },
      { "<leader>gC", function() neogit_for_buffer("commit") end, desc = "Neogit commit" },
      { "<leader>gp", function() neogit_for_buffer("pull") end,   desc = "Neogit pull" },
      { "<leader>gP", function() neogit_for_buffer("push") end,   desc = "Neogit push" },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    opts = {
      graph_style = "unicode",
      disable_hint = false,
      integrations = {
        diffview = true,
        -- telescope / fzf / snacks fallbacks are auto-detected
      },
      -- Open Neogit in a full tab so it doesn't fight for split space
      kind = "tab",
    },
  },

  -- GitHub permalink copier (replaces rb-github-link.el)
  -- Normal mode: line link. Visual mode: range link.
  -- Falls back to branch when HEAD isn't on a remote (same as the Emacs version).
  {
    "ruifm/gitlinker.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      {
        "<leader>gy",
        function() require("gitlinker").get_buf_range_url("n") end,
        desc = "Copy GitHub permalink (line)",
      },
      {
        "<leader>gy",
        function() require("gitlinker").get_buf_range_url("v") end,
        mode = "v",
        desc = "Copy GitHub permalink (range)",
      },
    },
    opts = {
      mappings = nil, -- suppress plugin defaults; we bind via `keys` above
    },
  },

  -- Side-by-side diff review (ediff/vdiff replacement)
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
    keys = {
      {
        "<leader>gd",
        function()
          local root = buffer_repo_root()
          if not root then
            vim.notify("Not in a git repo", vim.log.levels.WARN)
            return
          end
          vim.cmd("DiffviewOpen -C" .. vim.fn.fnameescape(root))
        end,
        desc = "Diffview (buffer's repo)",
      },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview file history (current file)" },
    },
    opts = {},
    config = function(_, opts)
      -- Re-configure diffview on VimResized so layout adapts to terminal width
      local function configure_diffview()
        local layout = vim.o.columns >= 160 and "diff2_horizontal" or "diff1_plain"
        require("diffview").setup(vim.tbl_deep_extend("force", opts, {
          view = {
            default = { layout = layout },
            file_history = { layout = layout },
          },
        }))
      end
      configure_diffview()
      vim.api.nvim_create_autocmd("VimResized", { callback = configure_diffview })
    end,
  },
}
