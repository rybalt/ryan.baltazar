# User Preferences

## Shell Tools

In Bash tool calls, prefer:

- `rg` (ripgrep) over `grep` for search; never use `grep`.
- `fd` over `find` for file search.
- `sd` over `sed` for text substitution.
- `jq` for JSON, `yq` for YAML.
- `tree` (depth-limited) over `ls -R` for directory structure.
- `tokei` for language/line-count summaries.

## File Formats

- Write all local documents (research plans, notes, design docs) and shared documents (READMEs, CI docs) in Markdown.

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

## Code Comments

Comments are the exception, not the norm. Write one only to explain the **why** behind a tricky line — never to restate
what the code does.

- Don't encode trivial history or decision logs in comments ("changed X to Y", "added for ticket Z"). That belongs in
  commit messages and PRs.
- A comment may note history _only_ when the code encodes an odd or quirky behavior that would otherwise look like a
  mistake — explain the quirk, not the changelog.
- Match the surrounding file's existing comment density; add nothing a competent reader wouldn't need.

## Writing Style

Applies to prose, docs, comments, and chat: write in Unity's technical-doc register. Concision is the priority. Cut
anything that adds no information.

- **Active voice.** "The system calls `Foo`", not "`Foo` is called by the system".
- **Present tense**, second person ("you"), imperative for steps.
- **Cut filler and hedging** — "in order to"→"to", "utilize"→"use", "is able to"→"can"; drop "basically / simply / just
  / actually / very / note that".
- **Drop qualifiers the context already carries** — "a broken command", not "a broken doctrine command", when the
  surrounding text has already established which command. Keep a modifier only when it disambiguates or adds
  information the reader doesn't have.
- **No nominalizations** — prefer the verb: "configure X", not "perform configuration of X".
- **State, don't pad.** Lead with the fact; skip throat-clearing preambles and closing summaries that restate what you
  just said.
- **Resolve references.** Name a thing before you refer to it; never let "it" or "the real X" stand for something you
  haven't stated.
- **Notation over prose.** Assume an expert reader (me). Prefer technical notation where it compresses: interval
  brackets (`[a, b)`), `iff`, set/logic symbols (`∈`, `⊆`, `⇒`), big-O. Don't spell these out into words. Technical
  shorthand (edge case, idempotent) is signal — keep it. This overrides Unity's register, which spells such things out
  for a general audience.

## Long Deliverables

Write long-form content (audit reports, migration plans, comprehensive reviews, type-binding tables, retrospectives) to
a file, not inline. In chat, return only:

- The file path
- A brief summary (top findings, headline counts, or the recommended next action)

If it's not obvious where the file belongs (project `docs/`, the PKM, or somewhere else), ask before writing rather than
guessing. This avoids truncation from the per-response output token cap and produces a reusable artifact. If the user
explicitly asks for full content in chat, override this rule.

## Delegation

Once a plan is formed and execution begins, scoped work goes to subagents by default, not the main thread. During
execution the main thread orchestrates: brief the subagent, review its output, integrate, and gate sign-off.

**Delegate by default when:**

- A plan exists with discrete, scoped steps (each with files, acceptance criteria, or pattern references)
- Work can be fanned out across independent units (parallel audits, bulk migrations, per-extension binding generation)
- The work is mechanical or pattern-following
- A read-only question about the codebase — "where/how is X done", "find the pattern for X", "does X exist",
  "validate X against the code" — comes up mid-task. Default these to `Explore` rather than running greps/reads
  inline. Inline reads land in the main-thread context; a delegated `Explore` returns only the conclusion, keeping
  the driver context lean. Read files inline only when you'll edit them or must reason over them line-by-line.

**Pick the right agent (and model tier):**

- Open-ended / read-only search across the codebase → `Explore` (`haiku`; `sonnet` if it needs light reasoning)
- Multi-step research questions → `general-purpose` (`sonnet`)
- Implementation diffs from a stacked-diff plan → `diff-coder` (specify model at dispatch; fallback `sonnet`)
- Diff review → `diff-reviewer` (specify model at dispatch; fallback `opus`)
- Plan design itself → `Plan`

Model tiering (the `model` override on `Agent`): mechanical search / existence / pattern-finding → `haiku`; light
research or synthesis → `sonnet`; judgment-heavy work (design, diff review, debugging from a hypothesis) → `opus`
(default). Cheaper models for the mechanical tiers; reserve `opus` for judgment.

**Dispatch discipline:**

- **Always specify the model at dispatch.** The agent frontmatter holds only a fallback tier — name the
  model on every `Agent` call so the tier is a deliberate choice per task, not an accident of the default.
- **Hand artifacts as file paths, never paste content.** Whatever a subagent reads or writes — a brief, a
  summary, a diff, search results, a generated file — passes as a path, not a pasted body, so it never
  re-enters the orchestrator's context. This is what keeps the driver context lean.
- **Batch small same-shape work into one dispatch.** When several changes share a shape (the same edit
  across N files, a set of parallel migrations), brief them together rather than one dispatch each.

**Do not delegate when:**

- The work is one or two trivial lines (overhead exceeds benefit)
- The scope is exploratory and likely to shift mid-execution
- The user has explicitly asked for direct hands-on work

Don't wait to be prompted — invoke the subagent once triggered. When a probe is read-only and you only need the
answer, delegating to `Explore` is the default, not the exception — even a single "where is X" is worth a cheap
subagent if it would otherwise pull file contents into the driver context.

## Diff Stack Workflow

Work in small, atomic diffs. Each diff is self-contained, testable, and requires explicit user sign-off before
proceeding to the next.

### Validate Premises Before Designing

When the work depends on a stated invariant ("X happens N times per frame", "Y always returns Z", "the count is
deterministic"), confirm it before designing around it. A short verification pass costs less than building
infrastructure on a wrong assumption.

Verification hierarchy, cheapest first:

1. **Static analysis** — read the code and trace the logic. Often sufficient; always cheaper than running things.
2. **Instrumentation** — add logging or a probe and observe actual behavior. Use when the question is about runtime
   ordering, timing, or behavior that static analysis can't reach.

When test results contradict a premise, the first move is to verify (read or instrument), not to propose a workaround.

### Dev Loop

Per-diff cycle (the orchestrator drives; subagents only implement and review):

1. **Brief and dispatch the implementer.** Slice the diff's plan section into a brief file:
   `gen-task-brief PLAN_FILE DIFF_ID` → `.claude/diffstack/<plan>/diff-<N>-brief.md`. Dispatch `diff-coder`
   with the four-field brief (where the diff fits; the brief-file path; interfaces from earlier diffs;
   ambiguity resolution) **and an explicit model** — paths, never pasted content. diff-coder returns a
   compact status block (`DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`) with its summary inline
   (files changed, key decisions, self-review, concerns). Read the status.
2. Compile and fix errors. The orchestrator does this — diff-coder never compiles, tests, stages, or commits.
3. Run relevant tests and fix failures.
4. **Package and review.** Build the working-tree review package:
   `gen-review-package .claude/diffstack/<plan>/review-<N>.diff`. Dispatch `diff-reviewer` (compact) with
   the package — the diff-file path, the brief-file path, and any verbatim
   `GLOBAL_CONSTRAINTS` — **and an explicit model**. **The subagent's response is not user-visible — echo the
   verdict block + findings inline before any next action.** If the verdict is `NEEDS_CHANGES` or `REJECT`,
   address the findings (re-brief `diff-coder` per `## Delegation`) and re-run from step 2. Cap at 2 attempts;
   on the 3rd, surface the diff + verdict to the user without further auto-iteration. (For manual review with
   multi-model fan-out, invoke `/diff-review --multi` directly instead — the subagent is single-model only.)
5. **Publish or stop.** Under the acceptance model (the default for a stack), on green + `LGTM` commit the
   diff provisionally and continue — see **Stack Acceptance Model** below. At horizon 1 (or a lone diff),
   this collapses to the hard gate: show the diff + verdict for user sign-off and **do not proceed to the
   next diff without explicit approval.**

### Stack Acceptance Model (run-ahead)

Decouples *publish* (commit) from *accept* (user sign-off). This is the default cadence for a stack;
horizon 1 (below) reduces it to the per-diff gate.

**Kickoff.** Run `diffstack init` once at the base — it sets `refs/diffstack/accepted/<branch>` to the
current tip. The provisional range is `accepted..HEAD`. The `refs/diffstack/*` namespace never pushes and
never shows on GitHub.

**Publish.** After a diff passes compile + tests (Dev Loop steps 2–3) **and** the verdict is `LGTM`, the
orchestrator commits it provisionally (one commit per diff) and continues to the next — it does NOT stop
for per-diff sign-off. `diff-coder` never commits. The whole provisional range is reversible with
`git reset --hard $(diffstack base)`.

**Leash — stop and request batch review at the FIRST of:**
1. **Verdict gate** — the diff-review verdict ≠ `LGTM`. Leave the tripping diff *uncommitted* in the
   working tree so the user sees it live.
2. **Escalation gate** — diff-coder returns `Status ∈ {DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT}`.
3. **Premise-failure gate** — a Validate-Premises check contradicts an assumption the plan relied on.
4. **Checkpoint gate** — the plan marks the diff `checkpoint` (e.g. after an architectural / public-API diff).
5. **Horizon gate** — the provisional count (`diffstack count`) reaches the horizon (default 3).

Gates 1–4 are risk-driven and always fire, so early-catch is preserved on the diffs that matter; gate 5 is
the tunable autonomy knob. The horizon count resets to 0 when the accepted ref advances.

**Batch review at a stop.** Package the provisional range — `gen-review-package "$(diffstack base)" HEAD
<outfile>` (range mode; pass base + HEAD as two args, not `$(diffstack range)` — that single `base..HEAD`
token is read as an OUTFILE) — plus any uncommitted tripping diff, and present the provisional commits with
their accumulated verdicts. Outcomes:
- **Accept all** → `diffstack accept` advances the ref to HEAD; check the covered `User sign-off` boxes.
- **Accept up to diff K** → `diffstack accept <K-sha>`; fold-down/restack the offending diff per
  `### Iterating within the stack`; the provisional commits above it restack.
- **Reject the range** → `git reset --hard $(diffstack base)`.

**Horizon config (three levels, narrowest wins).**
- CLAUDE.md default: `horizon = 3`.
- Per-plan: a `Horizon: N` field in the plan header, and a `checkpoint` tag on specific diff headings.
- Per-session: a user override ("run the whole stack, stop only on a gate", or "stop every diff" = horizon 1).

**Guardrail note.** In this loop the orchestrator commits (provisionally) — a deliberate, scoped relaxation
of the usual "the user stages and commits" guardrail. It is bounded to the diff-stack workflow and fully
reversible via the accepted ref. (Follow-up: update the `feedback_workflow_guardrails` memory post-merge.)

### Sign-off Checklists in Plan Files

Each diff in a plan file includes a `### Sign-off` section with a markdown checklist mirroring the acceptance criteria.
Check items (`[x]`) as you verify them. The **last item** in every sign-off checklist is always:

```
- [ ] User sign-off
```

Under the run-ahead model the acceptance items are checked by the agent as it verifies them, but the final
`User sign-off` item is checked in a **batch** — when the range covering that diff is accepted (`diffstack
accept`), tick every `User sign-off` box the acceptance covers. At horizon 1 it is checked per diff.

### Iterating within the stack

Most iteration happens at the stack tip. When a change belongs to a diff _below_ the tip, prefer to change at the tip
and fold down — it is generally cheaper: you skip cleaning and switching the working tree (which for a Unity worktree
forces a reimport and a native reload), and the fold restacks the descendants for you.

1. **Change at the tip, then fold down (preferred).** Make the change at the top, stage only the intended files, and
   fold them into the target commit with `git history fixup <commit> --update-refs=branches` (experimental — reads the
   staged index, rewrites the target, and restacks descendants).
2. **Switch down, then propagate.** Reach for this when folding is awkward — a large change, or one that conflicts when
   replayed and needs interactive resolution at the lower commit. Clean the working tree, `git switch` to the target
   commit or branch, make the change there, then update the descendants — the right command depends on whether you
   rewrote a commit:
   - Single commit per diff: `git amend` rewrites the commit, which abandons its descendants, so `git restack` (or
     `git amend` itself) replays them.
   - Stacked branches (GitHub-style): `git commit` adds a new commit and rewrites nothing, so nothing is abandoned and
     `git restack` is a no-op — rebase or `git move` the downstream branches onto the new tip instead.

Both assume the change lands _in_ the stack.

For experimental work, prefer a throwaway **stick of commits** over a stash. Commit the probe as its own commit off the
base or the tip, validate, then discard it with `git hide` (reversible) or `git undo`. A stash is a commit under the
hood but hard to reason over and easy to lose; a named commit stays visible in `git sl` and can never silently
contaminate a diff you later amend. Never mix throwaway changes into the working tree of a diff you intend to land.
