# rybalt deploy

Symlink-placer and bootstrap runner for the rybalt config repo. Discovers any
top-level subdir of the repo that contains a `deploy.yaml` and treats it as a
module. Adding a new module = drop the subdir in with a `deploy.yaml`; the
script auto-picks it up.

## Setup

One-time, per machine. The script runs on Python 3.9+ (macOS's bundled
`/usr/bin/python3` works fine), so you don't need brew's Python first.

```sh
# 1. Install homebrew (if not already)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Install the script's Python deps into your user site-packages
python3 -m pip install --user -r deploy/requirements.txt
#   ^^ if pip refuses with a PEP 668 "externally-managed-environment" error
#      (happens on brew's Python ≥ 3.11), add --break-system-packages. Don't
#      pass that flag with system Python 3.9 — its older pip doesn't know it.

# 3. Run the deploy. The first run's bootstrap phase will run brew bundle,
#    install python/fish/neovim/etc., and reorder your PATH (fish only).
./deploy/deploy.py
```

### Why the `--user --break-system-packages` dance

- `--user` installs into `~/Library/Python/<ver>/lib/python/site-packages/`,
  not the brew-owned `site-packages/`. Nothing brew-owned gets touched.
- `--break-system-packages` is required by [PEP 668](https://peps.python.org/pep-0668/)
  to opt out of brew's "externally-managed Python" protection. Combined with
  `--user`, the flag name is louder than what's actually happening — you're
  writing only to your user dir, not the brew dir.

The script uses `from __future__ import annotations` so modern type-hint
syntax (`str | None`, `list[X]`) never evaluates at runtime — that's why
the script parses and runs on 3.9 even though those hints would normally
require 3.10.

## Usage

```sh
# Interactive TUI — checkbox select of all discovered modules
./deploy/deploy.py

# Deploy everything, no TUI
./deploy/deploy.py --all

# Deploy a subset, no TUI
./deploy/deploy.py --modules fish,nvim

# Preview without performing any action
./deploy/deploy.py --dry-run --all

# Non-interactive: skip conflicts instead of prompting
./deploy/deploy.py --all --yes

# Skip the brew phase (Brewfile + per-module brew_packages)
./deploy/deploy.py --all --skip-brew

# Skip pre_link / post_link shell phases
./deploy/deploy.py --all --skip-shell
```

## What the script does

For every run, regardless of which modules are selected:

1. **PATH setup** — prepends brew's `bin/`/`sbin/` to the current process's
   PATH so subsequent subprocesses find brew-installed tools, and (if fish
   is installed) persists the same via `fish -c 'brew shellenv fish | source'`.
   That writes fish universal variables, so every future fish session also
   sees brew first. Idempotent. No-op for zsh/bash — those shells need
   `eval "$(brew shellenv)"` in your rc file manually.
2. **Brewfile** — if `deploy/Brewfile` exists and `brew` is on PATH, runs
   `brew bundle --file deploy/Brewfile`. Idempotent; brew skips already-
   installed formulae/casks. Never runs `brew bundle cleanup`.
3. **Repo-home symlink** — ensures `~/.config/rybalt` is a symlink to the
   repo root (the canonical path several configs reference at runtime).

Then for each selected module, in order:

1. `brew_packages` — `brew install <pkg>` for each entry.
2. `pre_link` — arbitrary shell commands run *before* links are placed
   (e.g. cloning a framework that owns the target directory).
3. `links` — places `target -> source` symlinks; conflicts on existing
   real files prompt `[s]kip / [b]ackup / [a]bort`.
4. `post_link` — arbitrary shell commands run *after* links exist.
5. `default_shell` — optional. If set (e.g. `fish`) and isn't already the
   user's `$SHELL`, prompts to `chsh` into it (and adds to `/etc/shells`
   first if needed).
6. `next_steps` — printed at the end of the run; never executed.

## Manifest schema (`<module>/deploy.yaml`)

Example using a hypothetical `mytool` module that exercises every field:

```yaml
# All fields optional except `links`.

brew_packages:
  # Module-specific brew formulae/casks. Baseline tools (ripgrep, fd, …) live
  # in deploy/Brewfile, not here. Flags allowed; whitespace-split and passed
  # to `brew install`. Prefer unpinned names.
  - mytool --with-extras

pre_link:
  # Shell commands run before links are placed. Idempotency is your
  # responsibility — guard with `test`, `||`, etc.
  - test -d ~/.mytool || git clone https://example.com/mytool-framework ~/.mytool

links:
  - source: config.toml           # path relative to module dir; "." for whole dir
    target: ~/.mytool/config.toml  # ~-expanded; absolute paths fine

post_link:
  # Shell commands run after links exist. Same idempotency rules.
  - mytool --bootstrap-plugins

default_shell: mytool-sh   # optional. If your $SHELL doesn't already point
                            # at this binary, the script prompts to chsh
                            # (and adds the path to /etc/shells via sudo
                            # if missing). Honors --yes (auto-decline) and
                            # --dry-run (describe).

next_steps:
  # Printed at end-of-run; not executed. For things that can't be automated
  # headlessly (e.g. in-app commands, fonts requiring user confirmation).
  - "Open mytool and run :install-extras once"
```

Look at the real per-module manifests (`claude/deploy.yaml`, `fish/deploy.yaml`,
etc.) for working examples — each uses a subset of the fields above.

## Conflict handling

When a `links:` entry's target already exists as something other than a
symlink to the repo:

- `[s]kip` (default; Enter) — leave the target alone, continue with the rest.
- `[b]ackup` — rename the target to `<name>.bak.YYYYMMDD-HHMMSS`, then place
  the symlink.
- `[a]bort` — stop the entire run.

`--yes` makes every conflict an auto-skip and emits a warning at the end.

## Known limitations

- **Brew flag re-application.** If a formula is already installed without
  the flags you've now declared (e.g. a package without `--with-some-option`),
  `brew install` is a no-op. To pick up new flags, `brew reinstall` manually.
- **No `brew bundle cleanup`.** The script never uninstalls things missing
  from the Brewfile. Run that manually if you want it.
- **macOS-flavored paths.** Ghostty target uses
  `~/Library/Application Support/...`. Other module manifests assume
  XDG-ish layouts that work on macOS and most Linuxes.

## Layout

```
deploy/
├── deploy.py          # entry point
├── Brewfile           # baseline formulae/casks/taps
├── README.md          # this file
└── requirements.txt   # PyYAML + questionary
```

Per-module manifests live alongside the module they describe:
`claude/deploy.yaml`, `fish/deploy.yaml`, `ghostty/deploy.yaml`, `nvim/deploy.yaml`.
