# APPEND_SYSTEM.md

Personal working preferences, appended to Pi's default system prompt. This is
the Pi analog of `claude/CLAUDE_home.md` (→ `~/.claude/CLAUDE.md`); it would
symlink to `~/.pi/agent/APPEND_SYSTEM.md`.

Pi is a **single-agent** harness: no subagents, no plan mode, no permission
gates, no built-in MCP. The delegation model from the Claude Code config does
not apply — do the work in one loop. See `pi/PLAN.md` for the transition
rationale and what was dropped.

Pi loads `CLAUDE.md` as a context file alongside `AGENTS.md` (both are
concatenated when present). This file has higher authority than those context
files: **ignore any subagent/delegation, auto-proceed-on-LGTM, auto-loop-commit,
or autonomy-roadmap sections of a loaded `CLAUDE.md`** — they are Claude
Code-specific and do not apply under Pi.

## Shell Tools

Prefer modern replacements in shell commands: `rg` over `grep`, `fd` over
`find`, `sd` over `sed`, `jq` for JSON, `yq` for YAML, `tree` (with depth
limits) over `ls -R`, `tokei` for line/language counts, `bat` over `cat` for
human-readable viewing, `delta` for diffs.

- Fall back to the classic tool when the modern one is missing or its flags
  don't cover the need — don't fail a task over tool preference.
- Prefer the `read` tool over `cat`/`bat` for inspecting files you intend to
  edit.

## File Formats

Local docs (research, plans, notes) and shared docs (READMEs, CI docs) are
Markdown.

## Design Question Tracking

In research/planning docs, track design questions as headings with a status tag
in backticks at the end: `OPEN`, `INVESTIGATING`, `RESOLVED`, `WONTFIX`.

```markdown
### DQ: Should we use approach A or B? `OPEN`
```

## Source File References

- `[DisplayName.cs](relative/path/to/file.cs)` for file links (paths relative to
  the document).
- Inline code `file.cs:42` for line-specific references. Verify line numbers
  against source before writing them — stale numbers are worse than none.
- Annotate read-only / prototype-branch files: `[File.cs](path) (prototype branch)`.

## Long Deliverables

Long-form content (audit reports, migration plans, comprehensive reviews,
retrospectives) goes to a file, not inline chat. In chat return only the file
path and a brief summary (top findings / headline counts / recommended next
action). If the destination isn't obvious (project `docs/`, the PKM, elsewhere),
ask before writing. Override only if the user explicitly asks for full content
inline.

## Diff Stack Workflow

Work in small, atomic diffs. Each diff is self-contained, testable, and gated on
explicit user sign-off before the next.

### Validate Premises Before Designing

When work depends on a stated invariant ("X happens N times per frame", "the
count is deterministic"), confirm it before designing around it. Cheapest first:
(1) static analysis — read the code and trace the logic; (2) instrumentation —
add a probe and observe actual behavior, for questions about runtime ordering or
timing. When a test result contradicts a premise, verify (read/instrument)
before proposing a workaround.

### Dev Loop (single-agent)

Per diff:

1. Make the change.
2. Build / compile-check.
3. Fix build errors.
4. Run the relevant tests.
5. Fix test failures.
6. Self-review the diff inline (the `diff-review` skill — single-model, run in
   this loop; there is no `diff-reviewer` subagent under Pi). Echo the verdict
   block + findings. If `NEEDS_CHANGES`/`REJECT`, address and re-run from step 2;
   cap at 2 auto-attempts, then surface the diff + verdict.
7. Show the diff + verdict for user sign-off. **Do not proceed to the next diff
   without explicit approval.** This is a hard gate.

(The Claude Code auto-proceed-on-LGTM and auto-loop-commit trials are
project-scoped to HandExtensibility under Claude Code and do not carry over to
Pi — user stages and commits.)

### Sign-off Checklists in Plan Files

Each diff in a plan file has a `### Sign-off` checklist mirroring its acceptance
criteria, items checked as verified. The last item is always `- [ ] User
sign-off` — a hard gate.
