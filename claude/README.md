# Claude Code Configuration

Global [Claude Code](https://docs.anthropic.com/en/docs/claude-code) preferences
that apply to all projects.

## Setup

Symlink `CLAUDE_home.md` into your Claude Code config directory:

```sh
ln -s ~/.config/rybalt/claude/CLAUDE_home.md ~/.claude/CLAUDE.md
```

This makes the preferences load automatically for every Claude Code session.
Project-level `CLAUDE.md` files layer on top for project-specific additions.

## Shell Tool Dependencies

The preferences reference CLI tools that Claude will use in Bash calls.
Install them with:

```sh
brew install ripgrep fd sd jq yq tree tokei
```

## What's in CLAUDE.md

- **Shell tools** — preferred CLI tools (`rg`, `fd`, `sd`, `jq`, `yq`, etc.)
- **File formats** — when to use org-mode vs Markdown
- **Org-mode conventions** — design question format, source file references
- **Diff stack workflow** — small atomic diffs with user sign-off gates
