-- C# LSP via Roslyn + Unity-aware file watching.
--
-- Stack:
--   - seblyng/roslyn.nvim   — Roslyn language server, multi-solution management
--   - roslyn-filewatch.nvim — Unity-aware file watcher (replaces roslyn's
--     built-in watcher which thrashes on Library/Temp/Logs churn)
--
-- Solution discovery:
--   roslyn.nvim's built-in broad_search is git-root-scoped — it scans
--   downward from the package's git root. In the hermetic workspace,
--   package source and TestProjects/ are siblings, so broad_search never
--   finds test project .sln files. We bypass roslyn.nvim's discovery
--   entirely with a custom root_dir override (via vim.lsp.config) that
--   scans TestProjects/ under the .projectile workspace root.
--
--   All .cs files in a session share one Roslyn client, rooted at the
--   active test project directory. Switch with :RoslynWorkspace.
--
-- Upstream only: do NOT use the Unity-focused roslyn.nvim fork. It
-- enables preprocessor branch dimming by default, which is noise for
-- cross-platform package code targeting many platforms simultaneously.

-- ── Helpers ──────────────────────────────────────────────────────────────

-- Walk up from CWD looking for .projectile (umbrella root), fall back to
-- nearest .git, fall back to CWD. Same algorithm as lua/rb/workspace.lua
-- (not yet wired up); inline here to avoid the dependency.
local function workspace_root()
  local cwd = vim.fn.getcwd()
  local markers = { ".projectile", ".git" }
  for _, marker in ipairs(markers) do
    local found = vim.fs.find(marker, { path = cwd, upward = true })[1]
    if found then
      return vim.fs.dirname(found)
    end
  end
  return cwd
end

-- Noise .sln files that should never be offered as Roslyn targets.
-- CI recipe solutions, native plugin build solutions, vendored SDK
-- solutions, and read-only prototype branches.
local NOISE_PATTERNS = {
  "Tools/CI/",
  "artifacts/",
  "Library/",
  "NativePlugin~/",
  "Submodules~/",
  "build%.gen%.sln",
  "%-ReadOnly/",
}

local function is_noise_sln(path)
  for _, pat in ipairs(NOISE_PATTERNS) do
    if path:find(pat) then
      return true
    end
  end
  return false
end

-- Scan for .sln files under the workspace's TestProjects/ directory
-- (and the workspace root itself). Returns absolute paths.
local function find_test_slns(root)
  local slns = {}

  -- Scan TestProjects/ subdirectories (one level deep — each subdir is
  -- a Unity project that may have a .sln at its root).
  local test_dir = root .. "/TestProjects"
  local handle = vim.uv.fs_scandir(test_dir)
  if handle then
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      if typ == "directory" then
        local sln_glob = vim.fn.glob(test_dir .. "/" .. name .. "/*.sln", false, true)
        for _, sln in ipairs(sln_glob) do
          if not is_noise_sln(sln) then
            slns[#slns + 1] = sln
          end
        end
      end
    end
  end

  -- Also check root level (some workspaces may have a .sln at the top).
  local root_slns = vim.fn.glob(root .. "/*.sln", false, true)
  for _, sln in ipairs(root_slns) do
    if not is_noise_sln(sln) then
      slns[#slns + 1] = sln
    end
  end

  return slns
end

-- ── :RoslynWorkspace command ─────────────────────────────────────────────

-- Pick the active .sln for the session. Stored in vim.g.rb_roslyn_workspace
-- and read by choose_target on the next LSP attach. Restarts the Roslyn
-- client to apply the change immediately.
vim.api.nvim_create_user_command("RoslynWorkspace", function()
  local root = workspace_root()
  local slns = find_test_slns(root)
  if #slns == 0 then
    vim.notify("No .sln files found under " .. root, vim.log.levels.WARN)
    return
  end

  -- Show short names in the picker, map back to full paths.
  local labels = {}
  for _, sln in ipairs(slns) do
    labels[#labels + 1] = vim.fn.fnamemodify(sln, ":~:.")
  end

  vim.ui.select(labels, { prompt = "Roslyn workspace:" }, function(_, idx)
    if not idx then return end
    local choice = slns[idx]
    vim.g.rb_roslyn_workspace = choice
    vim.notify("Roslyn workspace: " .. vim.fn.fnamemodify(choice, ":t"))
    vim.cmd("LspRestart roslyn")
  end)
end, { desc = "Pick active .sln for Roslyn LSP" })

-- ── Plugin specs ─────────────────────────────────────────────────────────

return {
  -- Mason: add community registry so :MasonInstall roslyn works.
  {
    "mason-org/mason.nvim",
    opts = {
      registries = {
        "github:mason-org/mason-registry",
        "github:Crashdummyy/mason-registry",
      },
    },
  },

  -- Disable nvim-lspconfig's built-in roslyn_ls — it auto-starts in
  -- Neovim 0.12+ and conflicts with roslyn.nvim (doubled diagnostics).
  {
    "neovim/nvim-lspconfig",
    init = function()
      vim.lsp.enable("roslyn_ls", false)
    end,
  },

  -- Roslyn C# LSP.
  -- lazy=false: plugin/roslyn.lua calls vim.lsp.enable("roslyn") which
  -- must run AFTER setup(opts). At startup no .cs buffers exist, so
  -- vim.lsp.enable just registers — the server starts later when a .cs
  -- file is opened, by which time our config + root_dir override are set.
  {
    "seblyng/roslyn.nvim",
    lazy = false,
    keys = {
      { "<leader>cs", "<cmd>RoslynWorkspace<cr>", desc = "Pick C# solution" },
    },
    config = function(_, opts)
      require("roslyn").setup(vim.tbl_deep_extend("force", opts, {
        filewatching = "off",
        lock_target = false,
      }))

      -- Override root_dir to bypass roslyn.nvim's git-root-scoped
      -- broad_search. Our root_dir is workspace-aware: it scans
      -- TestProjects/ under the .projectile root for .sln files.
      -- Returns the same directory for ALL .cs files in the session,
      -- ensuring a single Roslyn client instance.
      vim.lsp.config("roslyn", {
        root_dir = function(bufnr, on_dir)
          -- If a solution is already selected, reuse its directory.
          local selected = vim.g.roslyn_nvim_selected_solution
          if selected then
            on_dir(vim.fs.dirname(selected))
            return
          end

          -- Session override from :RoslynWorkspace.
          local override = vim.g.rb_roslyn_workspace
          if override and vim.uv.fs_stat(override) then
            on_dir(vim.fs.dirname(override))
            return
          end

          -- Check if the buffer is inside a directory with its own .sln
          -- (test project case — upward walk finds it directly).
          local buf_name = vim.api.nvim_buf_get_name(bufnr)
          local buf_dir = vim.fn.fnamemodify(buf_name, ":p:h")
          local ancestor_slns = vim.fs.find(function(name)
            return name:match("%.sln$") ~= nil
          end, { upward = true, path = buf_dir, limit = math.huge })

          for _, sln in ipairs(ancestor_slns) do
            if not is_noise_sln(sln) then
              on_dir(vim.fs.dirname(sln))
              return
            end
          end

          -- Package source case: no .sln in ancestor dirs.
          -- Scan TestProjects/ under the workspace root.
          local root = workspace_root()
          local slns = find_test_slns(root)

          if #slns >= 1 then
            on_dir(vim.fs.dirname(slns[1]))
            return
          end

          vim.notify(
            "No .sln found. Regenerate from Unity/Rider.",
            vim.log.levels.WARN
          )
          on_dir(nil)
        end,
      })
    end,
  },

  -- Unity-aware file watcher companion for roslyn.nvim.
  -- Replaces roslyn's built-in file watching (which we disabled above)
  -- with Unity-optimized logic: ignores Library/Temp/Logs churn,
  -- throttles diagnostics during heavy operations.
  {
    "khoido2003/roslyn-filewatch.nvim",
    ft = { "cs" },
    opts = {
      preset = "auto",
      client_names = { "roslyn" },
      deferred_loading = true,
      diagnostic_throttling = {
        enabled = true,
        debounce_ms = 500,
        visible_only = true,
      },
    },
  },
}
