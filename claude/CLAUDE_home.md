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

- All local documents (research plans, notes, design docs) and shared documents (READMEs, CI docs) should be written in Markdown.

## Design Question Tracking

When tracking design questions in research/planning documents, use markdown headings with status tags:

```markdown
### DQ: How should we handle X? `OPEN`
### DQ: Should we use approach A or B? `RESOLVED`
```

Status tags: `OPEN`, `INVESTIGATING`, `RESOLVED`, `WONTFIX`. Place the tag at the end of the heading in backticks.

## Source File References

When referencing source files in documents, use standard markdown:

- Use `[DisplayName.cs](relative/path/to/file.cs)` for file links. Paths should be relative to the document.
- For line-specific references, use inline code: `file.cs:42`.
- Verify line numbers against the actual source before writing them. Stale line numbers are worse than no line numbers.
- When referencing files from a read-only or prototype branch, annotate: `[File.cs](path) (prototype branch)`.

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

### Sign-off Checklists in Plan Files

Each diff in a plan file includes a `### Sign-off` section with a markdown
checklist mirroring the acceptance criteria. Items are checked (`[x]`) as they
are verified. The **last item** in every sign-off checklist is always:

```
- [ ] User sign-off
```

This is a hard gate. Claude must not proceed to the next diff until the user
explicitly approves.
