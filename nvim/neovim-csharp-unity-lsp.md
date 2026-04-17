# Neovim C# LSP & Unity Integration

Summary of decisions and options for the Claude Code agent to implement.

## Context

- **Editor**: Neovide (LazyVim base config)
- **Project structure**: Hermetic directory containing multiple repositories and test
  projects, where each test project defines its own C# solution (`.sln`)
- **Unity specifics**: OpenXR integration work inside Unity engine code; not a typical
  Unity game project. Rider is already in use for serious engineering work (debugging,
  deep refactoring). Neovide fills the "text editor" slot — quick edits, agent
  collaboration, research dives.
- **Goal**: Diagnostics, completions, go-to-definition, and refactoring in Neovide
  without duplicating Rider's role

---

## LSP Choice: Roslyn, not OmniSharp

OmniSharp is deprecated. The answer is the **Roslyn language server** — the same
server powering VS Code's C# extension and Rider's compiler integration.

**Do not use OmniSharp.** It has been abandoned upstream, has memory leak issues, and
uses older Roslyn APIs. All current community effort is on the Roslyn LSP path.

---

## Primary Plugin: `seblyng/roslyn.nvim`

The recommended Neovim plugin for C# LSP. Wraps the Roslyn language server with
multi-solution management features that nvim-lspconfig's basic roslyn support lacks.

### Installation

Roslyn is not in Mason's core registry. Add the community registry:

```lua
require("mason").setup({
  registries = {
    "github:mason-org/mason-registry",
    "github:Crashdummyy/mason-registry",
  },
})
```

Then `:MasonInstall roslyn`.

### Configuration

```lua
{
  "seblyng/roslyn.nvim",
  ft = "cs",
  opts = {
    broad_search = true,   -- walk upward through parent dirs to find .sln
    lock_target = false,   -- allow switching between solutions
    filewatching = "off",  -- CRITICAL for Unity: default causes huge perf drop
                           -- on projects with many files; roslyn-filewatch.nvim
                           -- handles file watching instead
  },
}
```

### Key features relevant to the project structure

- **Multi-solution support**: when opening a `.cs` file, walks upward through parent
  directories to find `.sln` files. If multiple are found, prompts for selection.
- **`:Roslyn target`**: switch the active solution at any time without restarting.
  `vim.g.roslyn_nvim_selected_solution` stores the current selection — expose in
  statusline if desired.
- **`ignore_target` callback**: Lua function to filter out solutions you never want to
  attach to. Useful for the hermetic multi-repo layout where naive discovery might pick
  the wrong `.sln`.
- **`choose_target` callback**: override the selection heuristic entirely with custom
  Lua. Useful if solution selection should be based on file path patterns.
- **Supports `.sln`, `.slnx`, `.slnf`** formats.
- **Source-generated file navigation**: handles `roslyn-source-generated://` URIs,
  which matters for Unity's source generators.

### Unity-specific concern: inactive preprocessor branches

**Out of scope. Do not enable.**

Inactive `#if` branch dimming (graying out code inactive under the current platform
defines) is explicitly unwanted. This codebase is cross-platform package code that
targets many platforms simultaneously — dimming would gray out large portions of
legitimate code depending on whichever platform the LSP happens to think is active.
This is noise, not signal, for a package author.

The Unity-focused roslyn.nvim fork enables this by default. **Use upstream
`seblyng/roslyn.nvim`** and do not configure any preprocessor dimming behavior.

---

## Companion Plugin: `khoido2003/roslyn-filewatch.nvim`

File watcher companion to roslyn.nvim. Handles the file watching that
`filewatching = "off"` disables, but does so with Unity-aware logic.

Unity constantly touches `Library/`, `Temp/`, `Logs/` during normal operation —
a naive file watcher causes constant LSP restarts and diagnostic thrashing.
roslyn-filewatch.nvim:

- Auto-detects Unity projects (presence of `Assets/`, `ProjectSettings/`)
- Ignores `Library`, `Temp`, `Logs`, `.vs`, `.idea` automatically
- Parses `.asmdef` files
- Throttles diagnostic updates during heavy operations (git checkout, Unity
  asset reimport) to prevent UI lag
- Debounces burst file changes (mass changes from Unity reimport trigger
  thousands of events)

```lua
{
  "khoido2003/roslyn-filewatch.nvim",
  ft = { "cs" },
  opts = {
    preset = "auto",         -- auto-detects Unity, applies optimized settings
    client_names = { "roslyn" },
    deferred_loading = true, -- wait until first .cs file is opened
    diagnostic_throttling = {
      enabled = true,
      debounce_ms = 500,
      visible_only = true,   -- only request diagnostics for visible buffers
    },
  },
}
```

Run `:checkhealth roslyn_filewatch` to verify setup. Run `:RoslynEngineInfo` to
confirm Unity mode is active.

---

## Optional: `bosvik/roslyn-diagnostics.nvim`

On-demand **workspace-wide** diagnostics. By default, Roslyn only surfaces diagnostics
for open files. This plugin lets you request diagnostics for the entire solution
(populates the quickfix list).

Useful for "show me all errors in this solution" without building. Complementary to
roslyn.nvim, not a replacement.

For large Unity solutions, configure roslyn.nvim to limit background analysis scope
to avoid crashes:

```lua
-- Inside roslyn.nvim settings
vim.lsp.config("roslyn", {
  settings = {
    ["csharp|background_analysis"] = {
      dotnet_analyzer_diagnostics_scope = "openFiles",
      dotnet_compiler_diagnostics_scope = "fullSolution",
    },
  },
})
```

---

## Build Diagnostics (dotnet build → quickfix)

Roslyn LSP surfaces analyzer diagnostics without actually invoking the compiler.
For true build output:

**Option A: overseer.nvim** (recommended — async task runner, routes output to
quickfix list, composable with other build tasks)

**Option B: easy-dotnet.nvim** — includes `:Dotnet build quickfix` among many other
dotnet workflow commands. Heavier plugin, more opinionated. Skip unless you want the
full suite (test runner, EF migrations, secrets management, etc.).

**Option C: simple keybinding** — sufficient for most cases:
```lua
vim.keymap.set("n", "<leader>db", ":!dotnet build<CR>", { desc = "dotnet build" })
```

---

## The .sln / .csproj Generation Problem

Roslyn LSP reads the `.sln` and `.csproj` files Unity generates — it cannot create
them. These files must exist and be up to date for LSP to work correctly.

### Options for keeping them current

**1. Rider (current workflow — keep this)**
Rider auto-regenerates via the JetBrains Rider Editor Unity package. Since Rider is
already in use for serious Unity work, the practical workflow is:
- Use Rider or Unity to generate files initially
- Regenerate when `.asmdef` files change, packages are added, or new assembly
  definitions are created
- Neovide/roslyn.nvim reads the generated files; works immediately after regeneration

**2. Unity Editor UI**
Edit → Preferences → External Tools → Regenerate Project Files. Check all boxes for
package `.csproj` generation. Does not require Rider.

**3. Unity batch mode (no UI)**
```bash
/path/to/Unity -batchmode -nographics -logFile - \
  -executeMethod UnityEditor.SyncVS.SyncSolution \
  -projectPath /path/to/project -quit
```
Only works when no other Unity instance has the project open. Scriptable from a
Makefile or shell alias.

**4. nvim-unity plugin**
Registers Neovim as a Unity external editor, adds regeneration under
Tools → Neovim Code Editor → Regenerate Project Files. Newer, less battle-tested.
Uses OmniSharp (not Roslyn) for LSP — skip the LSP part, but the editor registration
and regeneration trigger may still be useful.

### Staleness signal
When go-to-definition can't find a newly added type or `UnityEngine` namespace errors
appear, that's the signal the `.csproj` files are stale. Regenerate from Unity/Rider,
roslyn.nvim picks up changes automatically.

---

## Debugging

**Keep Rider for debugging.** Unity debugging in Neovim via nvim-dap is possible
(netcoredbg + Visual Studio Tools for Unity extension for the attach configuration)
but significantly more painful than Rider's integrated debugger. Not worth the effort
given Rider is already in the workflow.

If nvim-dap Unity support becomes desirable later, reference:
https://www.ownself.org/2025/setup-neovim-for-unity-development.html

---

## Recommended Plugin Stack Summary

| Plugin | Role | Priority |
|---|---|---|
| `seblyng/roslyn.nvim` | C# LSP, multi-solution management | Required |
| `khoido2003/roslyn-filewatch.nvim` | Unity-aware file watching | Required for Unity |
| `bosvik/roslyn-diagnostics.nvim` | On-demand workspace diagnostics | Optional |
| `stevearc/overseer.nvim` | Async build tasks → quickfix | Optional |

---

## Practical Workflow

1. Open Unity project in Unity Editor or Rider once to generate `.sln` + `.csproj`
2. Open Neovide at the hermetic directory root
3. Open a `.cs` file — roslyn.nvim walks upward, finds the `.sln`, attaches
4. Verify with `:checkhealth roslyn` and `:RoslynEngineInfo`
5. Use `:Roslyn target` to switch between solutions when moving between test projects
6. When `.csproj` files go stale, regenerate from Unity/Rider, continue in Neovide
7. For compilation errors: Rider or `dotnet build` → quickfix

---

## Open Questions for the Agent

1. **`choose_target` / `ignore_target` logic**: given the hermetic directory structure
   (multiple repos, each with its own `.sln`), does naive broad_search pick the right
   solution, or does it need a custom Lua predicate? The agent should test with a real
   `.cs` file from one of the test projects and check `:checkhealth roslyn` to verify
   the correct `.sln` was selected.

2. **Use upstream `seblyng/roslyn.nvim`**: the Unity-focused fork is explicitly out of
   scope. Preprocessor branch dimming is unwanted for cross-platform package code.

3. **`dotnet_analyzer_diagnostics_scope`**: for large Unity projects, start with
   `openFiles` for analyzer scope and `fullSolution` for compiler scope. Tune if
   Roslyn crashes or pegs the CPU.
