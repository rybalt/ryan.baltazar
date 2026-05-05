# Fish Prompt — Implementation Plan

Layer custom behavior on top of vendored [Hydro](https://github.com/jorgebucaran/hydro)
to handle long namespaced branch names, deep cwds, and large monorepos
without blocking the prompt — while preserving the ability to merge upstream
hydro changes.

## Goals

1. Sync fish config into the rybalt personal-config repo, alongside `nvim/` and `emacs/`.
2. Always-on path truncation: parents to single chars, leading-dot preserved.
3. Dynamic branch and git-base truncation when the status line exceeds 120 chars.
4. Fast prompts in monorepos: drop untracked enumeration, cache HEAD/index state, throttle background fetch.
5. Useful indicators: worktree, in-progress git state, ahead/behind, host context (SSH / nix-shell / container).
6. Multi-line layout: status line on top, prompt symbol on next line; vi-mode and command duration on the right prompt.
7. **Minimize fork surface** — hydro.fish stays as a near-pristine vendored copy. Our customizations live in a separate file that overrides exactly one upstream function.

## Architecture: layer on top of hydro

Hydro's prompt has four moving parts:

| Component | Function | Owned by |
|-----------|----------|----------|
| PWD formatting (string-only) | `_hydro_pwd` | hydro.fish — kept pristine |
| Async git data collection | `_hydro_prompt` | **the one fork point** — overridden by `_rb_prompt_run` |
| Cmd-duration / postexec tracking | `_hydro_postexec` | hydro.fish — kept pristine |
| Color/symbol var setup | inline at end of hydro.fish | hydro.fish — kept pristine |

The *renderer* (`fish_prompt.fish`) was never part of hydro.fish — it was
already in `~/.config/fish/functions/`, owned by us. So all visual layout
changes (multiline, right-prompt, host indicator, dynamic truncation) live in
our owned `fish_prompt.fish` / `fish_right_prompt.fish`.

`conf.d/rb-prompt.fish` is our override layer:

```fish
# Erase hydro's prompt event handler so ours takes over.
functions --erase _hydro_prompt

# Our replacement: same shape as _hydro_prompt, but with caching,
# untracked-disabled, throttled fetch, and worktree-aware in-progress detection.
function _rb_prompt_run --on-event fish_prompt
    # ...
end
```

When upstream hydro improves things outside `_hydro_prompt` (PWD logic,
postexec, var defaults), we sync `hydro.fish` and inherit them automatically.
When upstream changes `_hydro_prompt` itself, we manually port relevant
changes to `_rb_prompt_run`.

### Upstream sync procedure

`conf.d/hydro.fish` carries a header:

```fish
# Vendored from https://github.com/jorgebucaran/hydro/blob/main/conf.d/hydro.fish
# Last synced: 2026-05-05
# Upstream commit: <sha>
#
# Update with:
#   curl -L https://raw.githubusercontent.com/jorgebucaran/hydro/main/conf.d/hydro.fish \
#     -o fish/conf.d/hydro.fish
# Then bump the date and commit sha above.
```

Manual sync, no automation — fish prompt code changes rarely enough to not
warrant tooling.

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
├── fish_plugins                 # fisher only (hydro removed)
├── completions/
├── conf.d/
│   ├── hydro.fish               # vendored from upstream, near-pristine
│   ├── rb-prompt.fish           # our override layer
│   └── rustup.fish
├── functions/
│   ├── fish_prompt.fish         # owned by us, full rewrite for new layout
│   ├── fish_right_prompt.fish   # NEW — duration + vi-mode
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

## Diff 2: Vendor hydro + scaffold override layer

Stop fisher from managing hydro (so we can edit it freely), add an
upstream-tracking header to `conf.d/hydro.fish`, and create an empty
`conf.d/rb-prompt.fish` for future overrides. No behavior change.

**Files**
- Modify: `fish/fish_plugins` — remove `jorgebucaran/hydro`, keep `jorgebucaran/fisher`
- Modify: `fish/conf.d/hydro.fish` — prepend a header with upstream URL, current commit sha, last-sync date, and update procedure (see Architecture section)
- New: `fish/conf.d/rb-prompt.fish` — initially just a header comment describing its role; no logic yet

**Notes**
- After this diff, `fisher update` will not touch hydro (not in manifest).
- The hydro source itself is unchanged — same identifiers, same logic.
- `rb-prompt.fish` loads after hydro alphabetically (`h` < `r`), so future overrides will see hydro's definitions in scope.

### Sign-off

- [ ] `jorgebucaran/hydro` removed from `fish_plugins`
- [ ] `jorgebucaran/fisher` retained in `fish_plugins`
- [ ] `conf.d/hydro.fish` has upstream-tracking header but otherwise unchanged
- [ ] `conf.d/rb-prompt.fish` exists and loads cleanly (even though empty of logic)
- [ ] New shell renders the prompt visually identical to before
- [ ] `fisher update` does not reinstall or modify hydro
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

- [ ] Prompt renders on two lines: status line (line 1) + symbol line (line 2)
- [ ] Right prompt shows command duration after commands exceeding the threshold
- [ ] Right prompt shows `N`/`I`/`R`/`V` reflecting current vi mode
- [ ] Non-zero exit code displays before the prompt symbol on line 2
- [ ] `fish_mode_prompt` no longer renders inline
- [ ] User sign-off

---

## Diff 4: Path truncation defaults

Set `fish_prompt_pwd_dir_length=1` and verify Hydro's existing leading-dot
regex preserves dotted-dir prefixes correctly.

**Files**
- Modify: `fish/config.fish` (export `fish_prompt_pwd_dir_length=1`)
- Verify: existing regex `(\.?[^/]{N})[^/]*/` in `rb-prompt.fish` correctly preserves `.config` → `.c`

**Notes**
- Hydro's regex already preserves a leading `.`, so likely no regex change required. Verify against test cases:
  - `.config` → `.c`
  - `Code` → `C`
  - `com.unity.xr.hands` → `c` (since `.` only counts as leading)
  - `..hidden` → `.h` (leading dot, second dot literal)

### Sign-off

- [ ] In a deep cwd, parents render as single-char-plus-leading-dot
- [ ] Git base directory still renders in full (Hydro's existing behavior preserved)
- [ ] cwd basename still renders in full and bolded
- [ ] `.config` truncates to `.c` not `c`
- [ ] User sign-off

---

## Diff 5: Install `_rb_prompt_run` override; drop untracked detection

Erase hydro's `_hydro_prompt` event handler and register our own
`_rb_prompt_run --on-event fish_prompt`. The replacement is a copy of
`_hydro_prompt`'s body with the `git ls-files --others --exclude-standard`
block removed. This establishes the override pattern; later diffs (6, 7) extend
this same function.

**Files**
- Modify: `fish/conf.d/rb-prompt.fish` — add `functions --erase _hydro_prompt` and define `_rb_prompt_run`

**Notes**
- This is the **only** point where we copy logic from upstream hydro. All other diffs either work in our own files (`fish_prompt.fish` etc.) or extend `_rb_prompt_run`.
- New (untracked) files no longer trigger the `•` indicator. User confirmed acceptable.
- `_rb_prompt_run` continues to write to the per-pid universal var `$_hydro_git` so the existing repaint trigger and `fish_prompt.fish` reading logic both keep working untouched.

### Sign-off

- [ ] `_hydro_prompt` is no longer registered as an event handler (verify with `functions --handlers`)
- [ ] `_rb_prompt_run` is registered on `fish_prompt`
- [ ] `git ls-files --others` is no longer invoked from the prompt code path (verify by reading `_rb_prompt_run` body)
- [ ] Modifying a tracked file shows `•`
- [ ] Adding a new untracked file does not show `•`
- [ ] After `git add` of a new file, it is included in dirty detection (since it's now in the index)
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

Inside `_rb_prompt_run`, replace the `for fetch in $hydro_fetch false` loop
(carried over from upstream) with a time-throttled fetch that runs at most
once per repo per 10 minutes.

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
detected state writes into the same `$_hydro_git` universal var, prefixed/suffixed
into the formatted git string. No changes to `fish_prompt.fish`.

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

### DQ: Renaming hydro identifiers? `RESOLVED`

Resolved: do not rename. Keep `conf.d/hydro.fish` near-pristine to allow
upstream merges. Customizations live in `conf.d/rb-prompt.fish` as a layer.
