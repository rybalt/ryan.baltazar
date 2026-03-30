# User Preferences

## Shell Tools

- Prefer `rg` (ripgrep) over `grep` for all shell search operations. Do not use `grep` in Bash tool calls.
- Prefer `fd` over `find` for file searching in Bash tool calls.
- Prefer `sd` over `sed` for text substitution in Bash tool calls.
- Prefer `jq` for JSON parsing and manipulation in Bash tool calls.
- Prefer `yq` for YAML parsing and manipulation in Bash tool calls.
- Prefer `tree` (with depth limits) over `ls -R` for directory structure overview in Bash tool calls.
- Prefer `tokei` for codebase language/line count summaries in Bash tool calls.

## File Formats

- Documents intended for local reading (research plans, notes, design docs) should be written in Emacs org-mode format (`.org`), not Markdown. The user reads these files in Emacs where org-mode provides folding, TODO integration, and executable code blocks.
- Documents shared externally (GitHub READMEs, CI docs, files read by other tools or people) should remain Markdown.

## Org-mode Design Question Format

When tracking design questions in org-mode research documents, use the `DQ_` TODO keyword sequence. States, structure rules, property drawer conventions, and examples are defined in `~/.config/rybalt/emacs/rb-org-todos.el` — read that file for the full specification.

## Org-mode Source File References

When referencing source files in org-mode documents, use org file links instead of inline code markup:

- Use `[[file:relative/path/to/file.cs][DisplayName.cs]]` for file links. Paths should be relative to the org document.
- For line-specific references, use `[[file:path/to/file.cs::42][File.cs:42]]` — the `::linenum` syntax opens the file at that line in Emacs.
- Verify line numbers against the actual source before writing them. Stale line numbers are worse than no line numbers.
- When referencing files from a read-only or prototype branch, annotate the link: `[[file:path][File.cs]] (prototype branch)`.

## Diff Stack Workflow

Work in small, atomic diffs. Each diff is self-contained, testable, and requires
explicit user sign-off before proceeding to the next.

### Dev Loop

Per-diff cycle:
1. Make code changes
2. Check compilation
3. Fix compilation errors
4. Run relevant tests
5. Fix test failures
6. Show diff for user sign-off — **do not proceed to next diff without explicit approval**

### Sign-off Checklists in Plan Org Files

Each diff in a plan org file includes a `*** Sign-off` section with an org
checklist mirroring the acceptance criteria. Items are checked (`[X]`) as they
are verified. The **last item** in every sign-off checklist is always:

```
- [ ] User sign-off
```

This is a hard gate. Claude must not proceed to the next diff until the user
explicitly approves.
