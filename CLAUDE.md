# rybalt

Personal config repo. Each top-level directory is a self-contained tool
config that gets symlinked into the matching OS location on each machine.
The subdirectories share nothing at runtime.

The user's global Claude Code preferences live at
[claude/CLAUDE_home.md](claude/CLAUDE_home.md) and are already loaded as
`~/.claude/CLAUDE.md` in every session — do **not** re-read that file from
this repo unless the task is to modify it.

## Layout — read the authoritative doc for the subdir you're working in

| Dir        | Symlinked to                            | What it is                                    | Read this first                                                                 |
|------------|-----------------------------------------|-----------------------------------------------|---------------------------------------------------------------------------------|
| `claude/`  | `~/.claude/CLAUDE.md`                   | Global Claude Code preferences (one .md file) | [claude/README.md](claude/README.md)                                            |
| `emacs/`   | `~/.emacs.d/post-init.el`, `custom.el` (modules loaded from `~/.config/rybalt/emacs/`) | Emacs on top of minimal-emacs.d                | [emacs/README.org](emacs/README.org); deep design notes in [emacs/rybalt.org](emacs/rybalt.org) |
| `fish/`    | `~/.config/fish`                        | Self-owned fish prompt + shell config         | [fish/PLAN.md](fish/PLAN.md) — design history + current behavior across Diffs 1–10 |
| `ghostty/` | Contents merged into `~/.config/ghostty/` | Ghostty terminal config (single file)        | The file itself: [ghostty/config.ghostty](ghostty/config.ghostty)               |
| `nvim/`    | `~/.config/nvim`                        | LazyVim-based config                          | Plugin layer in [nvim/lua/plugins/](nvim/lua/plugins/); upstream docs at <https://lazyvim.github.io> |

When a task touches only one of these directories, read its doc and stay
local. Cross-subdir context is almost never needed.

## Repo conventions

- **Diff-stack workflow** from the user's global preferences applies: each
  substantive change is its own diff with a `### Sign-off` checklist gated
  on explicit user approval. [fish/PLAN.md](fish/PLAN.md) is the canonical
  worked example.
- **No top-level installer.** Bootstrap on a new machine is: clone → symlink
  the subdirs you want → install the CLI tools each subdir's README lists.
- **Working-tree path varies by machine.** Some machines clone to
  `~/src/rybalt`, others to `/opt/UnitySrc/repos/rybalt`; `~/.config/rybalt`
  is the stable symlink that other configs reference. Docs may use either
  path interchangeably.

## Gotchas

- The root `.gitignore` is a Unity-template leftover and tells you almost
  nothing about what's actually in this repo. Don't infer language or build
  layout from it.
- `.agent-shell/` (gitignored) holds local agent-shell transcripts and
  screenshots — not part of the published config.
- `nvim/README.md` is the stock LazyVim starter README and has no
  project-specific content; treat the `nvim/lua/` tree as the source of
  truth instead.
