---
name: diff-review
description: Review local code changes (git ref/range or working-tree) for correctness, project conventions, and test quality. Emits a structured verdict suitable for composition with auto-loop skills. Use for pre-push self-review, pre-sign-off review in the stacked-diff dev loop, or programmatic invocation by a wrapping skill. NOT for GitHub PRs — use the built-in /review skill for those.
---

# diff-review

Review local code changes against the conventions and patterns established in the project's `CLAUDE.md`. Adapted from the dotnet/roslyn `code-review` skill, generalized for any HPC# codebase.

**Reviewer mindset:** Be polite but very skeptical. Your job is to surface problems the author may have missed, question whether the change is needed at all, and verify claims rather than accepting framing. Treat commit messages and branch descriptions as claims to verify, not facts to accept. Probe edge cases. Flag concerns even when uncertain — surface them as low-confidence questions rather than silently dropping them.

## When to use

- Manual self-review of local changes before pushing or signing off
- Inside the stacked-diff dev loop, between `Run tests / fix failures` and `User sign-off` (gating step — see user CLAUDE.md `### Dev Loop`)
- As a primitive composed by a wrapping skill (e.g., a future `write-and-review` auto-loop)

**Do not use for GitHub PRs.** That's the built-in `/review` skill.

## Arguments (`$ARGUMENTS`)

| Arg | Meaning |
|---|---|
| `<git-ref>` or `<range>` | Review that ref or range. Examples: `HEAD~3..HEAD`, `main..feature/x`, `abc123`, branch name. |
| (no arg) | Review staged + unstaged working-tree changes. |
| `--multi` | Opt-in multi-model fan-out (default off). |
| `--full` | Force full output (default for manual invocation). |
| `--compact` | Force compact output (default when invoked from the dev loop or another skill). |

If neither flag is passed, default to `--full`. Programmatic consumers (the dev loop, future `write-and-review` skill) must pass `--compact` explicitly.

## Process

### Step 0 — Gather code context (no narrative yet)

Critically: **do NOT read commit messages, PR descriptions, or branch descriptions yet.** You must form your own independent assessment of what the code does, why it might be needed, and whether the approach is sound — before being exposed to the author's framing. Reading the narrative first anchors your judgment.

1. **Resolve diff scope.**
   - If `$ARGUMENTS` is a git ref or range: `git diff <range>` (or `git diff <ref>` for single-commit).
   - If no arg: `git diff HEAD` for working-tree (staged + unstaged combined).
2. **Read project conventions.** Walk up from the current working directory to find the closest project `CLAUDE.md` and read it in full. Pay particular attention to:
   - Sections labeled "conventions," "code style," "code review," or similar
   - Project-specific "never do these" rules
   - Marked hot paths or performance-sensitive areas
   - Test conventions, naming, and required attributes
   - The `## Review Noise` section if present — its patterns and coupling rules are used by the next sub-step and the relevance pass at the end of Step 0

   The user `CLAUDE.md` is already in your context via the harness — don't re-read it. The closest project CLAUDE.md adds project-specific rules on top.
3. **Classify changed files.** Invoke the `classify-changes` skill (default YAML output) on the same scope. (`classify-changes` reads the same project CLAUDE.md `## Review Noise` section you just read.) Use the categorized result to drive the rest of Step 0:
   - **`source`** — proceed to sub-steps 4-7 below for these files.
   - **`state`** and **`binary`** — acknowledge in the Holistic Assessment ("N project-state and M binary files modified, not deep-reviewed"); do NOT read their contents now (the relevance pass in 0.8 may revisit).
   - **`ide_artifact`** — emit a ⚠️ finding per file ("likely accidental commit — `<path>` matches an editor autosave/swap pattern"); do NOT read. Not re-evaluated in the relevance pass.
   - **`submodule`** — note in the verdict ("submodule pointer change in `<path>` — review separately by descending into the submodule"); do NOT attempt to flatten or read submodule internals from the parent repo.
4. **Read full source files.** For every file in the `source` bucket, read the **entire file** (not just hunks). Diff-only review is the #1 cause of false positives and missed issues — you need surrounding context to understand invariants, assumed contracts, and data flow.
5. **Read consumers and callers.** If the change modifies a public/internal API or a contract used elsewhere, grep for callers and read the relevant call sites. Understanding how the code is consumed reveals whether the change could break existing behavior.
6. **Read related utilities.** If the diff calls into shared helpers, read those to understand thread-safety, ownership, and lifetime contracts.
7. **Check git history.** Run `git log --oneline -20 -- <file>` for each `source` file. Look for related recent changes, reverts, or prior attempts to fix the same problem. Reveals churn or conflicts with recent work.
8. **Relevance pass on deferred files.** After reading source, revisit the files in `state` and `binary` you previously deferred (ide_artifacts were already flagged in step 3 and aren't re-evaluated). For each, judge whether it's coupled to a change you reviewed. Apply in order:
   1. **Project coupling rules.** If the project CLAUDE.md `## Review Noise` declares `### Coupling rules` (or similar), apply those first.
   2. **Generic coupling rules** (always check):
      - **Manifest ↔ lock file.** If a dependency manifest changed (`package.json`, `Cargo.toml`, `pyproject.toml`, etc.), the corresponding lock file should usually also change. Mismatch → ⚠️.
      - **Source ↔ sibling state.** When a project's ecosystem requires a sibling state file alongside each source file (declared in project CLAUDE.md `## Review Noise > Coupling rules`), check asymmetrically:
        - **Source added in diff** — the sibling must also be added in the diff. If the sibling exists only in the working tree (untracked), flag → ❌ (unstaged sibling won't reach CI).
        - **Source removed in diff** — the sibling must also be removed in the diff. If the sibling still exists in the working tree (orphan), flag → ❌ (orphan will conflict on next import/build).
   3. **Judgment call.** For any deferred file whose path or diff stat suggests it might be coupled to source you just read, deep-read it and incorporate into your assessment.

   Findings from this pass surface as regular ❌/⚠️ findings in Step 3 output. When a coupling check passes (e.g., `.meta` siblings correctly present), emit ✅ confirmations only when the coupling is load-bearing enough to be worth calling out (skip ✅ for trivial passes).

### Step 1 — Form an independent assessment

Based **only** on the code context (without commit messages or PR description), answer:

1. **What does this change actually do?** Describe the behavioral change in your own words from reading the diff and surrounding code. What was the old behavior? What is the new behavior?
2. **Why might this change be needed?** Infer the motivation from the code itself.
3. **Is this the right approach?** Would a simpler alternative be more consistent with the codebase? Could the goal be achieved with existing functionality? Are there correctness, performance, or safety concerns?
4. **What problems do you see?** Bugs, edge cases, missing validation, thread-safety, performance regressions, API design problems, test gaps, anything else that concerns you.

Write down this assessment internally before proceeding.

### Step 2 — Reconcile with author intent

Now read commit messages for the range, and any branch description (`git log --format=%B <range>`). Treat these as **claims to verify**, not facts to accept.

- If your independent reading disagrees with the author's framing, investigate further. Do not simply defer to the author.
- If your independent assessment found problems the narrative doesn't acknowledge, those problems are *more* likely to be real, not less.
- Update your assessment only if the new evidence genuinely changes it. Don't soften findings just because the commit message sounds reasonable.

### Step 3 — Detailed analysis

1. **Focus on what matters.** Prioritize bugs, performance regressions, safety issues, race conditions, resource management, incorrect assumptions, and API design problems. Don't comment on trivial style unless it violates a rule in the project CLAUDE.md.
2. **Consider collateral damage.** For every changed code path, brainstorm: what other scenarios, callers, or inputs flow through this code? Could any break or behave differently? If you identify any plausible risk — even one you can't fully confirm — surface it. The tradeoff is the author's call; your job is to make it visible.
3. **Be specific and actionable.** Every finding tells the author exactly what to change and why. Reference the relevant convention. Include evidence of how you verified the issue is real (e.g., "checked all 4 callers; none validate this parameter").
4. **Test Quality is a finding category** when the diff includes test files. Evaluate: regression coverage for the bug being fixed, positive AND negative paths, assertion strength (are they strong enough to catch the regression they're meant to catch?), no change-detector tests (asserting on observable contract, not implementation detail), test isolation, no over-broad mocking.
5. **Don't pile on.** If the same issue appears many times, flag once on the primary location with a note listing all affected files.
6. **Respect existing style.** When modifying existing files, the file's current style takes precedence over general guidelines.
7. **Don't flag CI-caught issues.** Skip anything a linter, typechecker, compiler, analyzer, or CI build step would catch (missing usings, formatting, unsupported syntax).
8. **Avoid false positives.**
   - Verify the concern actually applies given full context, not just the diff. Confirm the issue isn't already handled by a caller, callee, or wrapper.
   - Skip theoretical concerns with negligible real-world probability. "Could happen" ≠ "will happen."
   - If unsure, investigate further or surface as a low-confidence question, not a firm claim.
   - Trust the author's context. If a pattern seems odd but is consistent with the repo, assume it's intentional.
   - **Never assert that something "does not exist," "is deprecated," or "is unavailable" based on training data alone.** Your knowledge has a cutoff. When uncertain, ask rather than assert.
9. **Verify "convention" claims with a comprehensive count.** When you're tempted to frame something as an "established convention," "the codebase pattern," or similar, count the prior examples first (e.g. `rg` for the pattern across the project source tree). If N < 3 prior examples, do not call it a convention. Either:
   - Name the count explicitly: "1 prior example (`<file>`) follows this pattern" — and let the reader weigh the evidence.
   - Or reframe the finding scope-locally: "this diff has an internal inconsistency between X and Y" rather than appealing to a project-wide pattern.

   Convention claims based on N=1 evidence have produced false-confidence findings the reviewee correctly pushed back on. Cost a round-trip and weakened the signal of the rest of the review.
10. **Ensure code suggestions are valid.** Any code you suggest must be syntactically correct and complete.
11. **Label in-scope vs. follow-up.** Distinguish between issues this diff should fix and out-of-scope improvements. Be explicit when something is a follow-up rather than a blocker.

### Step 4 — (Optional) Multi-model fan-out

Only if `--multi` was passed. Different model families catch different classes of issues.

1. Inspect the available model list. Select 2-4 models from distinct model families (one Anthropic, one Google, one OpenAI, etc.). Pick the highest capability tier from each family ("standard" or "premium," not "fast/cheap/mini"). Do not select the same model running this primary review.
2. Spawn a sub-agent per model in parallel, giving each: the diff, the project CLAUDE.md content, the rules from this skill, and instructions to produce findings in the severity format below.
3. Wait for all agents (10-minute timeout per agent — proceed with what you have if one slow agent times out).
4. Synthesize: dedupe findings across models, elevate findings flagged by multiple models (higher confidence), include unique findings from individual models that meet the confidence bar.
5. Note in the output which models contributed.

### Step 5 — Emit verdict and findings

Produce the verdict block first (always), then findings in the requested format.

## Verdict block (always emitted)

Emit this exact YAML frontmatter at the top of the output. This is the contract for programmatic consumers (e.g., a wrapping auto-loop skill).

```yaml
---
verdict: LGTM | NEEDS_HUMAN_REVIEW | NEEDS_CHANGES | REJECT
blockers: <integer count of ❌ findings>
warnings: <integer count of ⚠️ findings>
suggestions: <integer count of 💡 findings>
multi_model: <true if --multi was used, else false>
report_file: <absolute path to the written report file, or empty string if findings were emitted inline>
---
```

## Verdict consistency rules

The verdict **must** be consistent with the findings.

1. **Verdict reflects the most severe finding.** Any ⚠️ finding rules out `LGTM`. Use `NEEDS_HUMAN_REVIEW` or `NEEDS_CHANGES` instead. Only emit `LGTM` when all findings are ✅ or 💡 and you are confident the change is correct and complete.
2. **When uncertain, escalate to `NEEDS_HUMAN_REVIEW`.** If you are unsure whether a concern is valid or whether you have enough context, escalate. A false LGTM is far worse than an unnecessary escalation.
3. **Separate code correctness from approach completeness.** A change can be correct code that is an incomplete approach (treats symptom not root cause, silently masks an error that should be diagnosed, fixes one instance but not others). The verdict must reflect the gap — don't let "the code itself looks fine" collapse to LGTM.
4. **Classify each ⚠️ and ❌ as merge-blocking or advisory.** For each, ask: "Would I be comfortable if this merged as-is?" If any answer is "no," verdict is `NEEDS_CHANGES`. If any is "I'm not sure," verdict is `NEEDS_HUMAN_REVIEW`.
5. **Devil's advocate check.** Re-read your ⚠️ findings. For each, ask: does this represent an unresolved concern about approach, scope, or risk of masking deeper issues? If so, the verdict must reflect that tension. Do not default to optimism because the diff is small.

## Severity tiers

- ❌ **error** — Must fix before merge/sign-off. Bugs, security issues, broken invariants, test gaps for behavior changes.
- ⚠️ **warning** — Should fix. Performance issues, missing validation, inconsistency with established conventions.
- 💡 **suggestion** — Consider changing. Style improvements, minor readability wins, optional optimizations.
- ✅ **confirmation** — Used in output to call out important aspects you verified are correct (e.g., "verified no callers depend on the removed behavior").

## Output formats

**Output destination — file vs. inline:** see the file-by-default rule under `## What NOT to flag`. Both formats below have a "file-pointer" variant (default) and an "inline" variant (only when the body is genuinely short, ≤ ~30 lines).

### Full (default for manual invocation)

**File-pointer variant (default — findings written to file):**

```
<verdict frontmatter — report_file: /path/to/diff-review-<scope>-<date>.md>

## diff-review — <scope description, e.g. HEAD~3..HEAD or working-tree>

**Verdict:** <verdict> (❌<n> ⚠️<n> 💡<n>)
**Report:** `/path/to/diff-review-<scope>-<date>.md`

**Top findings:**
- ❌ <one-line description> — `path/file.cs:42`
- ⚠️ <one-line description> — `path/file.cs:73`
- 💡 <one-line description> — `path/file.cs:200`

(See report file for Holistic Assessment and full detailed findings.)
```

The report file itself contains the full Holistic Assessment + Detailed Findings sections (same structure as the inline variant below).

**Inline variant (short reviews only, ≤ ~30 lines):**

```
<verdict frontmatter — report_file: "">

## diff-review — <scope description, e.g. HEAD~3..HEAD or working-tree>

### Holistic Assessment

**Motivation:** <1-2 sentences on whether the change is justified and the problem is real>

**Approach:** <1-2 sentences on whether the fix/change takes the right approach>

**Summary:** <verdict>. <2-3 sentence summary. If NEEDS_HUMAN_REVIEW, explicitly state which findings are uncertain and what a human reviewer should focus on.>

---

### Detailed Findings

#### ❌ <Category> — <brief description>

<file:line, evidence, what to change, reference to relevant convention>

#### ⚠️ <Category> — <brief description>

...

#### 💡 <Category> — <brief description>

...

#### ✅ <Category> — <brief description>

<things you verified are correct, when worth confirming>
```

### Compact (default for dev-loop / programmatic invocation)

**File-pointer variant (default — findings written to file):**

```
<verdict frontmatter — report_file: /path/to/diff-review-<scope>-<date>.md>

## diff-review: <verdict> (❌<n> ⚠️<n> 💡<n>)
Report: `/path/to/diff-review-<scope>-<date>.md`

❌ <one-line description> — `path/file.cs:42`
⚠️ <one-line description> — `path/file.cs:73`
(top findings only — see report for full list)
```

**Inline variant (short reviews only, ≤ ~30 lines):**

```
<verdict frontmatter — report_file: "">

## diff-review: <verdict> (❌<n> ⚠️<n> 💡<n>)

❌ <one-line description> — `path/file.cs:42`
❌ <one-line description> — `path/file.cs:108`
⚠️ <one-line description> — `path/file.cs:73`
💡 <one-line description> — `path/file.cs:200`
```

## Per-language addenda

The skill is a generic skeleton. Per-language sections below activate when files of that language appear in the diff. Project CLAUDE.md adds narrower rules on top (e.g., specific pool types, marked hot paths).

### C# addendum (HPC# defaults)

Activates when `.cs` files are in the diff.

- **Avoid LINQ in hot paths.** Trivial `.Any(...)` is fine. Otherwise prefer manual loops in performance-critical code. LINQ is acceptable in editor-only / tooling / test code.
- **Avoid `foreach` over collections without struct enumerators.** Prefer iteration paths that don't allocate an enumerator.
- **Avoid closures in hot paths.** When a lambda captures locals (creating a closure), refactor to avoid the capture or use a `static` lambda with explicit parameters.
- **Use pooled collections in hot paths.** Prefer pooled list/array/dict types (e.g. `ArrayPool<T>`, `UnityEngine.Pool.ListPool<T>`, project-provided pools) over fresh allocations. Specify capacity when known. Be careful to return pooled objects.
- **Avoid O(n²) patterns in hot paths.** Watch for linear scans inside loops, repeated dictionary rebuilds, or quadratic substring scans.
- **Cheap checks before expensive operations.** Null checks, kind checks, etc. before semantic-model calls or other expensive work.
- **`StringComparer.Ordinal` for internal comparisons.** Use ordinal comparison for identifiers and internal strings; only use culture-aware comparison for user-facing text.

The skill flags violations of these principles. The project CLAUDE.md decides what counts as a "hot path" and pins specific pool types. **If the project doesn't mark hot paths, only flag patterns that are clearly hot** (per-frame update loops, render callbacks, native interop boundaries, tight inner loops with measurable iteration counts). Do NOT broadly flag all non-test code as suspect — that produces noise that drowns out real findings. When unsure, skip the finding rather than emit a low-confidence ⚠️.

## What NOT to flag

- Issues a linter, typechecker, compiler, analyzer, or CI step would catch (missing usings, formatting, unsupported syntax). Assume CI runs separately.
- Theoretical concerns with no concrete trigger ("could happen" without evidence it will).
- Style not in the project CLAUDE.md or the per-language addendum here.
- Pile-on duplicate findings — consolidate to one comment per category, listing affected files.
- **Output destination — file by default, inline only when very short.**

  The verdict block (YAML frontmatter) is the consumer contract and is **always emitted inline** so callers can gate on it without reading a file. The `report_file` field in the frontmatter holds the path when written to a file, or an empty string when inline.

  The findings body follows this rule, regardless of invocation mode (`--full` or `--compact`):
  - **Default: write to a file.** Inline, emit only the verdict block + the report path + the top 3-5 findings as one-liners (so the consumer/user has signal without opening the file).
  - **Exception — inline-only when genuinely short:** if the rendered findings body is ≤ ~30 lines (verdict + a handful of one-line findings, no detailed analysis), emit inline and skip the file. When in doubt, write the file.

  **Path discovery (in order):**
  1. If the project CLAUDE.md pins a reviews directory (e.g. `## Reviews` section), use it.
  2. Else if `<repo-root>/docs/reviews/` exists (where `<repo-root>` = `git rev-parse --show-toplevel`), use it.
  3. Else if `<repo-root>/docs/` exists but `docs/reviews/` does not, fall back to `/tmp/` and suggest in the chat summary: "Consider creating `docs/reviews/` to track reviews in-repo." Do not auto-create.
  4. Else fall back to `/tmp/`.

  Filename: `diff-review-<short-scope>-<YYYY-MM-DD>.md`. If the file exists, append `-<HHMM>` to disambiguate.

  Rationale: inline dumps of long reviews have repeatedly hit output token limits and lost sessions. File-first protects the conversation budget; the verdict block keeps the contract intact.

## Composition

This skill is a primitive. It composes downward (uses) and upward (is used by):

**Uses:**
- **`classify-changes`** — Step 0.3 invokes it to bucket files into source / state / binary / ide_artifact / submodule. Lets diff-review skip noise without re-implementing classification logic. Project-specific noise patterns live in the project CLAUDE.md `## Review Noise` section, which `classify-changes` reads.

**Used by:**
- **The stacked-diff dev loop** (`~/.claude/CLAUDE.md` `### Dev Loop`) invokes `/diff-review --compact` and gates user sign-off on the verdict. If `NEEDS_CHANGES` or `REJECT`, the loop addresses findings and re-runs, capped at 2 attempts before surfacing.
- **A future `write-and-review` auto-loop skill** (not yet built) will iterate `diff-coder` ↔ `diff-review` until the verdict is clean. The verdict block above is the contract.

Keep the verdict block stable across versions; downstream skills depend on it.
