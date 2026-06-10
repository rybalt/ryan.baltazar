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

## Long Deliverables

Long-form content (audit reports, migration plans, comprehensive reviews, type-binding tables, retrospectives) should be written to a file rather than emitted inline. In chat, return only:
- The file path
- A brief summary (top findings, headline counts, or the recommended next action)

If it's not obvious where the file belongs (project `docs/`, the PKM, or somewhere else), ask before writing rather than guessing. This avoids truncation from the per-response output token cap and produces a reusable artifact. If the user explicitly asks for full content in chat, override this rule.

## Delegation

Once a plan is formed and you're entering execution, scoped pieces of work go to subagents by default — not the main thread. The main thread's role during execution is orchestration: brief the subagent, review its output, integrate, gate sign-off.

**Delegate by default when:**
- A plan exists with discrete, scoped steps (each with files, acceptance criteria, or pattern references)
- Work can be fanned out across independent units (parallel audits, bulk migrations, per-extension binding generation)
- The work is mechanical or pattern-following

**Pick the right agent:**
- Implementation diffs from a stacked-diff plan → `diff-coder`
- Open-ended search across the codebase → `Explore`
- Multi-step research questions → `general-purpose`
- Plan design itself → `Plan`

**Do not delegate when:**
- The work is one or two trivial lines (overhead exceeds benefit)
- The scope is exploratory and likely to shift mid-execution
- The user has explicitly asked for direct hands-on work

This is a hard default, not a soft preference. Don't wait to be prompted — invoke the subagent as soon as the trigger conditions are met.

## Diff Stack Workflow

Work in small, atomic diffs. Each diff is self-contained, testable, and requires
explicit user sign-off before proceeding to the next.

### Validate Premises Before Designing

When the work depends on a stated invariant ("X happens N times per frame",
"Y always returns Z", "the count is deterministic"), confirm it before
designing around it. A short verification pass costs less than building
infrastructure on a wrong assumption.

Verification hierarchy, cheapest first:
1. **Static analysis** — read the code and trace the logic. Often
   sufficient; always cheaper than running things.
2. **Instrumentation** — add logging or a probe and observe actual
   behavior. Use when the question is about runtime ordering, timing, or
   behavior that static analysis can't reach.

When test results contradict a premise, the first move is to verify (read
or instrument), not to propose a workaround.

### Dev Loop

Per-diff cycle:
1. Make code changes
2. Check compilation
3. Fix compilation errors
4. Run relevant tests
5. Fix test failures
6. Delegate to the `diff-reviewer` subagent (compact mode) for the verdict. **The subagent's response is not user-visible — echo the verdict block + findings inline before any next action.** If verdict is `NEEDS_CHANGES` or `REJECT`, address findings (re-delegate fixes per `## Delegation`) and re-run from step 2. Cap at 2 attempts; on the 3rd, surface the diff + verdict to the user without further auto-iteration. (For manual review with multi-model fan-out, invoke `/diff-review --multi` directly instead — the subagent is single-model only.)
7. Show diff + diff-review verdict for user sign-off — **do not proceed to next diff without explicit approval**

### Sign-off Checklists in Plan Files

Each diff in a plan file includes a `### Sign-off` section with a markdown
checklist mirroring the acceptance criteria. Items are checked (`[x]`) as they
are verified. The **last item** in every sign-off checklist is always:

```
- [ ] User sign-off
```

This is a hard gate. Claude must not proceed to the next diff until the user
explicitly approves.
