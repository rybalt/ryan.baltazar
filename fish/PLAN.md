# Fish Prompt — Implementation Plan

Build a self-owned fish prompt that handles long namespaced branch names,
deep cwds, and large monorepos without blocking the prompt. No upstream
prompt-plugin dependency; portable to a fresh machine via `clone + symlink`.

## Goals

1. Sync fish config into the rybalt personal-config repo, alongside `nvim/` and `emacs/`.
2. Always-on path truncation: parents to single chars, leading-dot preserved.
3. Dynamic branch and git-base truncation when the status line exceeds 120 chars.
4. Fast prompts in monorepos: skip untracked enumeration, cache HEAD/index state, throttle background fetch.
5. Useful indicators: worktree, in-progress git state, ahead/behind, host context (SSH / nix-shell / container).
6. Multi-line layout: status line on top, prompt symbol on next line; vi-mode and command duration on the right prompt.
7. **Self-contained** — no Hydro/fisher entanglement. Bootstrap is `clone rybalt → symlink ~/.config/fish → done`.

## Architecture: self-owned, no upstream prompt plugin

We previously planned to fork Hydro. Two issues surfaced during Diff 2
implementation that made that plan untenable:

1. **The existing `fish_prompt.fish` doesn't use Hydro.** It calls fish's
   built-in `prompt_pwd` and `fish_vcs_prompt`, ignoring the
   `$_hydro_pwd` / `$$_hydro_git` / `$_hydro_status` variables Hydro
   computes. Hydro was loaded but unused — the actual prompt is fish's
   default-style.
2. **Hydro's plugin source ships our renderer.** Hydro provides
   `functions/fish_prompt.fish` and `functions/fish_mode_prompt.fish`,
   not just `conf.d/hydro.fish`. Fisher's update logic is `cp -RLf`
   (unconditional overwrite), so any `fisher update` would clobber our
   customized renderer (Diff 3+) and vi-mode neutralizer.

The pragmatic fix is to drop Hydro entirely. The 70-80 lines of fish that
provide value (PWD truncation regex, async git subshell, postexec duration
tracking) get written directly into our own `conf.d/rb-prompt.fish`. We own
the whole stack.

Component map after the redo:

| Component | Lives in | Notes |
|-----------|----------|-------|
| Renderer | `functions/fish_prompt.fish` | Reads vars set by `rb-prompt.fish`; assembles status line + handles prompt symbol on line 2 |
| Right prompt | `functions/fish_right_prompt.fish` | Cmd duration + vi-mode letter (NEW in Diff 3) |
| Vi-mode hook | `functions/fish_mode_prompt.fish` | No-op (Diff 3) |
| Async git data collection | `conf.d/rb-prompt.fish` | `_rb_prompt_run --on-event fish_prompt` (Diff 5) |
| PWD formatting | `conf.d/rb-prompt.fish` | `_rb_prompt_pwd --on-variable PWD` (Diff 4) |
| Postexec / cmd duration | `conf.d/rb-prompt.fish` | `_rb_prompt_postexec --on-event fish_postexec` (Diff 3) |
| Color/symbol defaults | `conf.d/rb-prompt.fish` | Set at end of file (Diff 3 onward) |

`fisher` itself stays installed (`jorgebucaran/fisher` remains in
`fish_plugins`) for future plugin needs unrelated to the prompt. No prompt
plugin is installed; the prompt is entirely our own files.

### Bootstrap on a new machine

```fish
# 1. Install fish (brew install fish, or apt, etc.)
# 2. Bootstrap fisher (one-time, for future plugins)
curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher
# 3. Clone rybalt
git clone <rybalt-url> /opt/UnitySrc/repos/rybalt
# 4. Symlink fish config
ln -s /opt/UnitySrc/repos/rybalt/fish ~/.config/fish
# 5. Open a new shell. Done — prompt works offline thereafter.
```

No `fisher install` is required for the prompt itself; everything ships in
the rybalt repo.

## Workflow

Work happens on the `claude/clever-hawking-6bb367` worktree branch.
**`~/.config/fish` is symlinked to the worktree path during development**
(Option A). After the branch merges to main, we re-point the symlink to
`/opt/UnitySrc/repos/rybalt/fish/`.

## Design summary

Status line layout:

```
[host?] cwd | [wt:name?] branch [⏸ rebase 3/7?] ↑n ↓m •      ≤120 chars
[err?]❱                                          [duration] [N]
```

Compression order when status line > 120 chars:

1. Shrink git-base directory dot-aware (`com.unity.xr.hands` → `c.u.x.h`).
2. Middle-ellipsize branch namespace (`rybalt/hand-extensibility/050-foo` → `rybalt/…/050-foo`).
3. Allow overflow (leaf is sacred; cwd basename is sacred).

Path truncation default state: parent dirs to 1 char, leading-dot preserved.
Git base full. cwd full and bolded. (This is `fish_prompt_pwd_dir_length=1`
applied to Hydro's existing logic.)

Performance model:

- Drop `git ls-files --others` entirely (no untracked detection).
- HEAD/index/packed-refs mtime cache, worktree-id keyed, 60s TTL backstop.
- `git fetch --no-tags` throttled to once per repo per 10 minutes via stamp file.
- Async git block (Hydro's existing `fish --private --command "..." &` pattern).

Indicators:

- Worktree: `[wt:<name>]` before branch when `git rev-parse --git-dir` is under `worktrees/`.
- In-progress git state via filesystem checks on `$GIT_DIR`:
  - `rebase-merge/` or `rebase-apply/` → recover real branch from `head-name`, show progress
  - `MERGE_HEAD` / `CHERRY_PICK_HEAD` / `BISECT_LOG` → state markers
- Host context (concatenated when multiple apply):
  - `$SSH_CONNECTION` set → `[hostname]`
  - `$IN_NIX_SHELL` set → `[nix:$name]`
  - `/.dockerenv` exists or `$container` set → `[container]`
- Ahead/behind: keep current display; visually flag both-nonzero divergence as a force-with-lease cue.

Dropped: untracked counting, branchless smartlog integration, detached-HEAD subject enrichment.

## Sync layout

```
/opt/UnitySrc/repos/rybalt/fish/
├── .gitignore                   # ignores fish_variables
├── PLAN.md                      # this file
├── config.fish
├── fish_plugins                 # jorgebucaran/fisher only (no prompt plugin)
├── completions/
│   └── fisher.fish
├── conf.d/
│   ├── rb-prompt.fish           # data collection + PWD format + postexec + defaults
│   └── rustup.fish              # rustup completion (unrelated)
├── functions/
│   ├── fish_prompt.fish         # renderer
│   ├── fish_right_prompt.fish   # cmd duration + vi-mode (NEW in Diff 3)
│   ├── fish_mode_prompt.fish    # no-op stub
│   └── fisher.fish
└── themes/
```

`~/.config/fish` becomes a symlink to that directory. `fish_variables` lives
inside the symlink target but is gitignored (machine-local interactive state).

---

# Diff stack

Each diff is self-contained, testable, and gated by user sign-off. The last
checklist item in every Sign-off section is `[ ] User sign-off` — work does
not advance to the next diff without it.

---

## Diff 1: Sync skeleton

Move `~/.config/fish` contents into `<rybalt>/fish/` and replace the original
location with a symlink. No prompt behavior changes.

**Files**
- New: `fish/config.fish`, `fish/conf.d/*`, `fish/functions/*`, `fish/themes/*`, `fish/completions/*`, `fish/fish_plugins`
- New: `fish/.gitignore` (one line: `fish_variables`)
- Filesystem: `~/.config/fish` becomes a symlink

**Notes**
- Preserve a backup of the original `~/.config/fish` before moving (e.g. `~/.config/fish.bak.YYYYMMDD`) in case rollback is needed.
- Decide symlink target (Option A vs B in Workflow section) at sign-off.

### Sign-off

- [x] All current `~/.config/fish` files (including `fish_variables`) live under the worktree `fish/` directory; `fish_variables` is gitignored so it stays out of version control
- [x] `~/.config/fish` is a symlink to the worktree `fish/` directory (Option A — re-point to main after merge)
- [x] `fish/.gitignore` excludes `fish_variables`
- [x] Original config preserved at `~/.config/fish.bak.2026-05-05` until sign-off
- [ ] New shell session loads cleanly and renders the unmodified Hydro prompt
- [ ] User sign-off

---

## Diff 2: Drop hydro entirely; scaffold rb-prompt

Hydro is removed from `fish_plugins`, the vendored `conf.d/hydro.fish` is
deleted, and `conf.d/rb-prompt.fish` is created as an empty scaffold for
future data-collection logic. The renderer (`functions/fish_prompt.fish`)
and vi-mode handler (`functions/fish_mode_prompt.fish`) stay as they are —
they were already user-customized and don't depend on Hydro.

**Why drop instead of fork** — see [Architecture](#architecture-self-owned-no-upstream-prompt-plugin)
section. Two reasons in short: the existing `fish_prompt.fish` doesn't read
Hydro's data, and Hydro's plugin source ships our renderer files (so any
`fisher update` would clobber Diff 3+).

**Files**
- Modify: `fish/fish_plugins` — remove `jorgebucaran/hydro`, keep `jorgebucaran/fisher`
- Delete: `fish/conf.d/hydro.fish`
- New (or revised): `fish/conf.d/rb-prompt.fish` — empty scaffold with a doc comment; no logic yet

**One-time runtime steps** (user runs in any fish session):

```fish
# Remove hydro from fisher's plugin tracking (matches the manifest)
set -U _fisher_plugins jorgebucaran/fisher

# Erase fisher's per-plugin file ownership record for hydro
set -e _fisher_jorgebucaran_2F_hydro_files
```

These can't be done in code — they update fish universal variables, which
are machine-local interactive state.

**Notes**
- No prompt plugin is now installed. The prompt is entirely our own files.
- `jorgebucaran/fisher` stays for future plugin needs (none today).
- `functions/fish_prompt.fish` and `functions/fish_mode_prompt.fish` were
  originally installed by fisher as part of hydro, but fisher's tracking
  of them is removed by the second `set -e` above. We own them outright.
- `_rb_prompt_run` (Diff 5) and `_rb_prompt_pwd` (Diff 4) will be written
  from scratch into `rb-prompt.fish` — equivalents of Hydro's logic but
  fully under our control.

### Sign-off

- [ ] `jorgebucaran/hydro` removed from `fish_plugins`
- [ ] `jorgebucaran/fisher` retained in `fish_plugins`
- [ ] `fish/conf.d/hydro.fish` does not exist
- [ ] `fish/conf.d/rb-prompt.fish` exists with doc comment + `status is-interactive || exit`
- [ ] New fish shell loads conf.d without errors
- [ ] User has run `set -U _fisher_plugins jorgebucaran/fisher`
- [ ] User has run `set -e _fisher_jorgebucaran_2F_hydro_files`
- [ ] `fisher list` reports only `jorgebucaran/fisher`
- [ ] `set --names | rg '_fisher_.*hydro'` returns nothing (regex must be quoted; `*` is a fish glob)
- [ ] User-visible: prompt renders identically to Diff 1 (since the existing renderer didn't use Hydro anyway)
- [ ] User sign-off

---

## Diff 3: Layout switch — multiline + right prompt

Move from single-line to two-line layout. Add `fish_right_prompt`. Make
`fish_mode_prompt` a no-op (vi mode moves to right prompt).

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` (set multiline, move last-status display to line 2)
- Modify: `fish/functions/fish_prompt.fish` (rewrite for new layout)
- New: `fish/functions/fish_right_prompt.fish` (renders cmd-duration + vi-mode letter)
- Modify: `fish/functions/fish_mode_prompt.fish` (return empty)

**Notes**
- Last-status code (e.g. `[127]`) renders inline before the prompt symbol on line 2 when nonzero, in red.
- Right prompt: `[<duration>] [<vi-letter>]`. Either may be empty.

### Sign-off

- [x] Prompt renders on two lines: status line (line 1) + symbol line (line 2). Note: existing prompt was already two-line; only the error-code position changed.
- [x] Right prompt shows command duration above the 1s threshold (e.g. `[2.5s]`, `[1m 5s]`, `[1h 2m 3s]`)
- [x] Right prompt shows `N`/`I`/`R`/`V` reflecting current vi mode when vi keybindings active
- [x] Non-zero exit code displays before the prompt symbol on line 2 (e.g. `[1] ❯`)
- [x] `fish_mode_prompt` is a no-op (returns empty)
- [ ] User sign-off

---

## Diff 4: PWD formatter and path truncation

Implement `_rb_prompt_pwd --on-variable PWD` in `conf.d/rb-prompt.fish`.
This computes a formatted PWD string into `$_rb_prompt_pwd` whenever the
current directory changes. Honors `fish_prompt_pwd_dir_length=1` for parent
shrinking, preserves leading dots, keeps the git-base directory full, and
bolds the cwd basename.

The renderer (`functions/fish_prompt.fish`, rewritten in Diff 5) reads
`$_rb_prompt_pwd` instead of calling fish's `prompt_pwd`.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` — define `_rb_prompt_pwd` and the variable handler
- Modify: `fish/config.fish` — export `fish_prompt_pwd_dir_length=1`

**Notes**
- The truncation regex is `(\.?[^/]{N})[^/]*/` — match leading-dot-optional + N chars, replace any further chars before `/`. Verified against test cases:
  - `.config` → `.c` (leading dot preserved, then 1 char)
  - `Code` → `C`
  - `..hidden` → `.h` (leading dot, second dot is the 1 char)
- Git base directory is detected via `git rev-parse --show-toplevel`. If the cwd is inside a git repo, the basename of that path is preserved verbatim.
- cwd basename gets ANSI bold (`\x1b[1m...\x1b[22m`).
- Logic conceptually similar to Hydro's `_hydro_pwd` (good reference) but written fresh — no `_hydro_*` symbols.

### Sign-off

- [ ] In a deep cwd, parents render as single-char-plus-leading-dot
- [ ] Git base directory renders in full
- [ ] cwd basename renders in full and bolded
- [ ] `.config` truncates to `.c` not `c`
- [ ] `_rb_prompt_pwd` updates on `cd` (verified by inspecting the var)
- [ ] User sign-off

---

## Diff 5: Implement async git data collection

Define `_rb_prompt_run --on-event fish_prompt` in `conf.d/rb-prompt.fish`.
This is the data-collection layer: kick off a backgrounded `fish --private`
subshell that reads `branch`, `dirty (tracked-only)`, and `ahead/behind`,
writing the formatted result to a per-pid universal variable that triggers
prompt repaint.

This is also the diff where the renderer (`functions/fish_prompt.fish`) is
rewritten to read those values and emit them in the new layout.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` — define `_rb_prompt_run`, the per-pid var, and the variable-watcher that triggers repaint
- Modify: `fish/functions/fish_prompt.fish` — rewrite to consume the new vars (replaces fish-default `prompt_pwd` / `fish_vcs_prompt` calls)

**Notes**
- Logic lifted in spirit from Hydro's `_hydro_prompt` (good reference for fish async patterns) but written from scratch — no `_hydro_*` symbols.
- Untracked files are not detected (Hydro's `git ls-files --others` block is *not* ported). User confirmed acceptable.
- Pattern: per-pid universal var `_rb_prompt_git_$fish_pid` holds the formatted git string. A variable-watcher on that name calls `commandline --function repaint` to refresh the prompt when the async subshell finishes.

### Sign-off

- [ ] `_rb_prompt_run` is registered on `fish_prompt` (verify with `functions --handlers`)
- [ ] `git ls-files --others` is not invoked anywhere in `conf.d/rb-prompt.fish`
- [ ] Modifying a tracked file shows `•`
- [ ] Adding a new untracked file does not show `•`
- [ ] After `git add` of a new file, it is included in dirty detection
- [ ] Prompt renders correctly with the rewritten `fish_prompt.fish`
- [ ] User sign-off

---

## Diff 6: HEAD/index cache

Add a cache layer in front of the async subshell inside `_rb_prompt_run`.
Skip the subshell entirely when cached values are valid. Cache key includes
worktree-id and mtimes of HEAD, index, and packed-refs. 60s TTL.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` — extend `_rb_prompt_run` with cache short-circuit before the `fish --private --command "..." &` call

**Notes**
- Cache key: `<git-dir-path>:<HEAD-mtime>:<index-mtime>:<packed-refs-mtime>`
- Stored in fish universal vars or a tmpfs file (`/tmp/rb-prompt-cache-$USER`)?
  Decide at implementation time; lean toward universal vars for simplicity.
- Worktree-aware because `git rev-parse --git-dir` returns
  `.git/worktrees/<name>` for worktrees, distinct per worktree.
- TTL is a backstop for vectors we don't catch (e.g., user manually edits
  refs, branchless rewrites history). 60s is a starting point; revisit if
  staleness shows up in practice.

### Sign-off

- [ ] Within 60s in the same repo with no git state change, prompt does not spawn the async subshell
- [ ] After `git checkout`, cache invalidates and a new subshell runs
- [ ] After `git add`, cache invalidates (index mtime changed)
- [ ] After `git fetch`, cache invalidates (packed-refs mtime changed)
- [ ] In two worktrees of the same repo, cache entries are independent
- [ ] User sign-off

---

## Diff 7: Throttled background fetch

Inside `_rb_prompt_run`, add a time-throttled background fetch that runs at
most once per repo per 10 minutes.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` — modify the fetch logic inside `_rb_prompt_run`'s subshell command

**Notes**
- Stamp file: `$GIT_DIR/.rb-prompt-last-fetch` (worktree-aware via `$GIT_DIR`).
- Fetch runs `git fetch --no-tags --quiet` in background, output to `/dev/null`.
- Default: on. Configurable via `rb_prompt_fetch_interval` (seconds; default 600).
- Skip fetch if repo has no remotes.

### Sign-off

- [ ] First prompt in a repo with stale stamp triggers a fetch
- [ ] Subsequent prompts within the throttle window do not trigger fetch
- [ ] After window expires, next prompt triggers fetch
- [ ] Fetch runs in background; prompt does not block on network
- [ ] Repo with no remotes does not attempt to fetch
- [ ] User sign-off

---

## Diff 8: Worktree + in-progress indicators

Add `[wt:<name>]` worktree marker and detect rebase/merge/cherry-pick/bisect
state. During rebase, recover the real branch name from
`$GIT_DIR/rebase-merge/head-name`.

Worktree and in-progress detection happen inside `_rb_prompt_run`'s subshell
(it has `git rev-parse --git-dir` and filesystem access already). The
detected state writes into the same `$_rb_prompt_git_$fish_pid` universal var,
prefixed/suffixed into the formatted git string. No changes to `fish_prompt.fish`.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` — extend `_rb_prompt_run` subshell to detect worktree and in-progress state, fold into output string

**Notes**
- Worktree detection: `git rev-parse --git-dir` matches `*/worktrees/<name>$`.
- Rebase detection: `test -d $GIT_DIR/rebase-merge` or `test -d $GIT_DIR/rebase-apply`.
  - Branch name from `cat $GIT_DIR/rebase-merge/head-name` (strip `refs/heads/`).
  - Progress from `cat $GIT_DIR/rebase-merge/msgnum` and `.../end`.
- Merge: `test -e $GIT_DIR/MERGE_HEAD` → marker `⇄ merge`.
- Cherry-pick: `test -e $GIT_DIR/CHERRY_PICK_HEAD` → marker `⇒ cherry-pick`.
- Bisect: `test -e $GIT_DIR/BISECT_LOG` → marker `⇆ bisect`.

### Sign-off

- [ ] Inside a worktree: `[wt:<name>]` appears before branch
- [ ] In a regular checkout: no worktree marker
- [ ] During `git rebase -i HEAD~3`: shows real branch + `⏸ rebase n/m` progress
- [ ] During `git merge` with conflict: shows merge marker
- [ ] During `git cherry-pick`: shows cherry-pick marker
- [ ] During `git bisect`: shows bisect marker
- [ ] User sign-off

---

## Diff 9: Host / context indicator

Render `[hostname]` / `[nix:<name>]` / `[container]` at the start of the
status line when applicable. Concatenate when multiple apply.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` or `fish/functions/fish_prompt.fish`
  (add prefix detection)

**Notes**
- SSH: `set -q SSH_CONNECTION` or `set -q SSH_TTY`. Hostname from `(hostname -s)` or `$HOSTNAME`.
- nix-shell: `set -q IN_NIX_SHELL`. Name from `$name` (set by nix-shell) when available.
- Container: `test -e /.dockerenv` or `set -q container`.
- Local non-special shell: render nothing.

### Sign-off

- [ ] Local shell: no host marker rendered
- [ ] Inside SSH session: `[<hostname>]` rendered
- [ ] Inside nix-shell: `[nix:<name>]` rendered (or `[nix]` if name unset)
- [ ] Inside container: `[container]` rendered
- [ ] When multiple apply (e.g., SSH + nix): both render concatenated
- [ ] User sign-off

---

## Diff 10: Dynamic 120-budget truncation

Compute visible width of status line and apply compression in order:
git-base shrink → branch middle-ellipsize → overflow.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` (post-process `_rb_prompt_pwd` and branch string before assigning to universal vars)

**Notes**
- Visible width measurement: strip ANSI escapes, then `string length`.
- Budget: 120 chars on line 1 only (status line). Configurable via `rb_prompt_max_width`.
- Compression algorithm:
  1. Render full version. Measure.
  2. If over budget: shrink git-base segment dot-aware (`com.unity.xr.hands` → `c.u.x.h`). Re-measure.
  3. If still over: middle-ellipsize branch (`first-segment/…/leaf`). Re-measure.
  4. If still over: render as-is, accept overflow.
- Branch ellipsis only applies when branch has 3+ segments. With 2 segments, no middle to ellipsize — leaf is sacred so render full.
- With 1-segment branch (e.g., `main`): no compression possible on branch.
- Edge case: cwd is exactly the git base (`pwd` == `git_root`) — git-base shrink applies directly.

### Sign-off

- [ ] Short branch + short cwd, under budget: status line renders full
- [ ] Short branch + long cwd, over budget: git-base shrinks dot-aware; branch untouched
- [ ] Long branch + long cwd, still over after git-base shrink: branch middle-ellipsizes
- [ ] Truly excessive: line renders without crash, may wrap (overflow accepted)
- [ ] 2-segment branch over budget: leaf preserved, no middle to ellipsize, overflow accepted
- [ ] 1-segment branch over budget: no branch compression, overflow accepted
- [ ] `rb_prompt_max_width=80` overrides the default budget
- [ ] User sign-off

---

# Open questions tracked during implementation

### DQ: Symlink target — worktree path or main? `RESOLVED`

Resolved: Option A (worktree path during dev, re-point to main after merge).

### DQ: Cache storage — universal vars or tmpfs file? `OPEN`

Universal vars are fish-native and survive shell restarts. Tmpfs file is
simpler to invalidate and inspect. Decide at Diff 6.

### DQ: Hydro fork vs. self-owned implementation? `RESOLVED`

Resolved during Diff 2 implementation: drop Hydro entirely. The original
"layer on top of Hydro" approach was untenable because (1) the existing
`fish_prompt.fish` didn't actually read Hydro's data, and (2) Hydro's
plugin source ships our renderer files, which `fisher update` would clobber
unconditionally. Self-owned is the only safe path.
