# WezTerm migration plan

Move the terminal + multiplexer layer from Ghostty + tmux to WezTerm on macOS.
Diff-stack workflow per [repo CLAUDE.md](../CLAUDE.md); each diff is self-contained,
testable, and gated on explicit user sign-off.

**Scope: WezTerm on macOS only.** No Windows/PowerShell port, no Python rewrite of
the bash tooling. [statusline.sh](../claude/statusline.sh) and fish keep running
unchanged under bash on macOS. Cross-platform is a later, separate effort.

## Why WezTerm

GPU-rendered multiplexer with real scrollback (not tmux's line-based copy-mode), and —
via a `wezterm-mux-server` unix domain — persistent sessions that survive GUI restarts,
covering the tmux detach/reattach pattern in one Lua config.

## What migrates

| Component | Action |
|---|---|
| [nvim/lua/plugins/tmux.lua](../nvim/lua/plugins/tmux.lua) | Swap `vim-tmux-navigator` → `smart-splits.nvim` (drives both tmux and WezTerm) — Diff 1 |
| `wezterm/` (new) | Lua config mirroring [ghostty/config.ghostty](../ghostty/config.ghostty) — Diff 2 |
| [tmux/.tmux.conf](../tmux/.tmux.conf) workflow | Reimplement in WezTerm Lua — Diff 3 |

Everything else (`claude/`, `fish/`, `deploy.py`) is untouched. Ghostty and tmux stay
deployed and working until Diff 3 is signed off, so the migration is non-destructive
and reversible at every step.

---

## Diff 1: Decouple nvim from tmux-navigator

Replace `vim-tmux-navigator` with `smart-splits.nvim`, which drives seamless C-hjkl
pane navigation against **both** tmux and WezTerm (and native nvim splits). Keeps tmux
working today; unblocks the WezTerm multiplexer swap in Diff 3.

**Files:** [nvim/lua/plugins/tmux.lua](../nvim/lua/plugins/tmux.lua) → rename to
`navigation.lua`; swap spec to `mrjones2014/smart-splits.nvim`, remap C-hjkl to
`require('smart-splits').move_cursor_*`.

**Acceptance:**
- C-hjkl still moves between nvim splits and (under current tmux) between tmux panes.
- `lazy-lock.json` updated; no dangling `vim-tmux-navigator` reference.

### Sign-off
- [x] `smart-splits.nvim` spec replaces `vim-tmux-navigator` (`tmux.lua` → `navigation.lua`)
- [ ] C-hjkl verified across nvim splits + tmux panes (needs `:Lazy sync` + hands-on)
- [ ] `lazy-lock.json` regenerated (drops `vim-tmux-navigator`, adds `smart-splits` on sync)
- [ ] User sign-off

---

## Diff 2: Stand up the WezTerm module (config + keybindings, no multiplexer)

Create the `wezterm/` module mirroring [ghostty/config.ghostty](../ghostty/config.ghostty)
plus a `leader`-based key table that mirrors the [tmux/.tmux.conf](../tmux/.tmux.conf)
muscle memory. Deployed **alongside** Ghostty so you A/B without losing the old setup.
Keybindings live here (not Diff 3) because they're non-destructive — no mux domain,
persistence, or copy-model change yet.

**Files:**
- `wezterm/wezterm.lua` — OS-following color scheme (built-in `Catppuccin Latte` when
  light, `Catppuccin Mocha` when dark) via `get_appearance()` + a `window-config-reloaded`
  live-switch; the fancy tab bar frame/cells recolor per flavor too (not part of a
  `color_scheme`), active tab in mauve; `FiraCode Nerd Font Mono` @ 12;
  `scrollback_lines = 10000`; cursor no-blink; both Option keys as Meta (the
  `macos-option-as-alt` equivalent); the key table below.
- `wezterm/deploy.yaml` — symlink to `~/.config/wezterm/wezterm.lua`; `platform: darwin`.

### Keybindings (tmux-mirror)

`leader = CTRL+Space` (timeout ~1s), matching the tmux prefix. `LEADER CTRL+Space`
sends a literal C-Space through (tmux's `send-prefix`).

| Intent | tmux binding | WezTerm | Fidelity |
|---|---|---|---|
| Split side-by-side | `prefix %` | `LEADER %` → `SplitHorizontal` | exact |
| Split stacked | `prefix "` | `LEADER "` → `SplitVertical` | exact |
| Pane nav (vim-aware) | `C-hjkl` (no prefix) | `CTRL+hjkl` → `is_nvim`-gated callback (SendKey to nvim, else `ActivatePaneDirection`) | seamless nvim↔pane handoff (pulled fwd from Diff 3) |
| Editor layout (new tab) | `prefix e` | `LEADER e` → callback: left 60%, right col split 50/50, focus left | exact (mux `pane:split`) |
| Reshape to main-vertical | `prefix E` | — | **dropped** (WONTFIX): no WezTerm `select-layout` preset; `prefix e` covers it |
| Grow / shrink pane | `prefix >` / `<` | `LEADER >` / `<` → `AdjustPaneSize` | **approx**: incremental, not absolute `-y 80%` |
| Balance split 50/50 | `prefix \|` | — | **deferred**: no WezTerm balance/equalize action; relative `AdjustPaneSize` can't hit 50/50 reliably |
| New tab | `prefix c` | `LEADER c` → `SpawnTab` | exact |
| Workspace switcher | `prefix s` | `LEADER s` → `ShowLauncherArgs{FUZZY\|WORKSPACES}` | exact (session → workspace) |
| Rename tab | `prefix ,` | `LEADER ,` → `PromptInputLine`→`SetTabTitle` | exact |
| Activate tab N | `prefix N` | `LEADER 1..9` → `ActivateTab(N-1)` | exact (tmux base-index 1) |
| Zoom pane | `prefix z` | `LEADER z` → `TogglePaneZoomState` | exact |
| Close pane | `prefix x` | `LEADER x` → `CloseCurrentPane{confirm=true}` | exact |
| Reload config | `prefix r` | `LEADER r` → `ReloadConfiguration` | exact |

Deferred to Diff 3 (need the mux domain / copy model): `prefix d` detach,
`prefix C` claude-primary popup, the Chrome-style copy-mode + `y`→clipboard.

**Not ported:** Ghostty's `global:ctrl+grave quick_terminal` is a macOS-only Ghostty
feature with no WezTerm equivalent (see DQ).

### Colors

OS-following Catppuccin (Latte light / Mocha dark), matching ghostty + nvim. The scheme,
the fancy tab bar frame, and the tab cells all switch per flavor — the tab bar is not part
of a `color_scheme`, so it's recolored explicitly. Two color layers still matter:
- **Self-emitted RGB (no risk):** nvim (`catppuccin/nvim`, `term_colors = true`) and the
  tmux catppuccin status bar emit truecolor directly; they only need WezTerm's truecolor
  passthrough (native). Unaffected.
- **Named-ANSI (visual check):** [colors.fish](../fish/conf.d/colors.fish) and
  [statusline.sh](../claude/statusline.sh) use ANSI *named* colors that ride the terminal's
  16-color palette. Accepting WezTerm's built-in Catppuccin as-is; just eyeball the prompt +
  statusline once per flavor. If a slot looks off vs Ghostty, an OSC-4 probe + explicit
  palette pin is the fallback — not built up-front.

**Acceptance:**
- `wezterm --config-file wezterm/wezterm.lua` launches in the flavor matching the OS, and
  switches live (scheme + tab bar) when the OS appearance toggles.
- fish prompt + `statusline.sh` read correctly in both flavors; nvim truecolor confirmed.
- Every keybinding-table row works; the `approx` resize rows and the deferred `prefix E` /
  `LEADER |` are documented in-config with a comment stating the WezTerm limitation.
- `deploy.py --dry-run --modules wezterm` shows the intended symlink; Ghostty untouched.

### DQ: Replacement for the global quick-terminal drop-down? `WONTFIX`
Dropped. No WezTerm equivalent to Ghostty's global `ctrl+\``; not worth an external
hotkey tool. Revisit only if the global summon is missed.

### DQ: `prefix E` main-vertical reshape? `WONTFIX`
Dropped — wasn't useful in practice. `prefix e` (fresh-tab editor layout) covers the case.

### Sign-off
- [x] `wezterm.lua` renders OS-following Catppuccin (scheme + tab bar) + font + scrollback
- [x] Live switch on OS appearance toggle verified (scheme + tab bar, both flavors)
- [x] fish prompt + statusline + nvim colors read correctly in both flavors (visual check)
- [x] Keybinding table works end-to-end; approximations + deferrals commented in-config
- [ ] `wezterm/deploy.yaml` discovered by `deploy.py`, dry-run clean
- [ ] Ghostty config still deployed and working (non-destructive)
- [x] Quick-terminal + `prefix E` DQs resolved (both dropped)
- [ ] User sign-off

---

## Diff 3: Reimplement the tmux workflow in WezTerm

The largest diff — a reimplementation, not a port. [tmux/.tmux.conf](../tmux/.tmux.conf)
encodes the workflow in tmux primitives (`set-hook`, `if-shell`, `display-popup`,
`copy-pipe`); WezTerm expresses the same intent in Lua events + key tables.

The `leader` + key table already landed in Diff 2. This diff adds the pieces that need
the mux domain or a changed input/render model:
- **Persistence** (tmux detach/attach) → `wezterm-mux-server` **unix domain**; GUI
  attaches on startup, sessions survive GUI restart. Adds `LEADER d` detach.
- **`after-new-window` auto-naming** ([auto-name-window.sh](../tmux/scripts/auto-name-window.sh))
  → `format-tab-title` event computing `<cwd-basename> (N)` in Lua (no shell script).
- **Chrome-style copy-mode + `y`→`pbcopy`** → built-in `copy_mode` key table +
  `CopyTo 'Clipboard'` (no-auto-copy model from the tmux config).
- ~~**`smart-splits.nvim` handoff**~~ → **DONE (pulled forward into Diff 2).** WezTerm side
  uses an `is_nvim` user-var gate (self-contained, no `wezterm.plugin.require`); nvim side
  loads eagerly and pins `multiplexer_integration` by direct-terminal detection (`$TMUX`
  first, then `$WEZTERM_PANE`), so the WezTerm behavior — emitting `IS_NVIM`, `wezterm cli`
  edge handoff — fires iff WezTerm is the direct terminal (never through a tmux layer).
  `CTRL+hjkl` flows into and out of nvim splits + WezTerm panes.
- **Status bar** → rebuild the catppuccin/tmux top status (session/dir/host/battery/clock)
  as a WezTerm `format-tab-title` / status event; auto-switch flavor with appearance.
- **`prefix+C` claude-primary popup** → see DQ; hardest to replicate.

**Acceptance:**
- Mux-server session persists across a full GUI quit/relaunch; `LEADER d` detaches.
- Tab titles auto-name from cwd with same-basename suffixing.
- Copy-to-clipboard reproduces the no-auto-copy model; `CTRL+hjkl` hands off to nvim.
- Status bar renders the equivalent modules and follows light/dark.

### DQ: `claude-primary` popup replacement? `OPEN`
WezTerm has no `display-popup`. Candidates: a dedicated tab/window attached to the mux
domain (persistent, one keybind to focus); a spawned overlay window; or an OS-hotkey
approach shared with the Diff 2 quick-terminal DQ. Decide before implementing.

### DQ: Retire the `tmux/` module after cutover? `OPEN`
Keep `tmux/` in-repo through Diff 3 as the fallback while the WezTerm mux is on trial.
Decide whether to archive it (→ `archive/`) once the WezTerm workflow is proven.

### Sign-off
- [ ] Mux-server persistence verified across GUI restart
- [ ] Layouts / resize / copy / nav reproduced
- [ ] Tab auto-naming in Lua (script-free)
- [ ] `claude-primary` DQ resolved and implemented
- [ ] `tmux/` retire-vs-keep DQ resolved
- [ ] User sign-off

---

## Open questions (rollup)

- **DQ Diff 2:** quick-terminal drop-down replacement? `WONTFIX` (dropped)
- **DQ Diff 2:** `prefix E` main-vertical reshape? `WONTFIX` (dropped)
- **DQ Diff 3:** `claude-primary` popup replacement? `OPEN`
- **DQ Diff 3:** retire `tmux/` after cutover? `OPEN`
