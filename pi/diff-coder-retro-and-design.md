# diff-coder — Retro & Pi Design

Retrospective on the Claude Code `diff-coder` subagent (a few months of use) and
the forward design for a **Pi-only** replacement built on Pi's `subagent`
example extension.

**Status:** design aligned, not yet built (2026-06-10).
**Scope:** Pi-only. The Claude Code `~/.claude/agents/diff-coder.md` is *reference to learn from*, not a maintenance target.
**Mode:** single-agent Pi orchestrator delegating implementation diffs to a cheaper (sonnet) worker process.

> Note: Pi has no built-in subagent concept. All "agent"/"delegation" machinery
> here is provided by the `subagent` *extension* (and its `~/.pi/agent/agents/`
> convention), not Pi core.

---

## TL;DR

A few months of `diff-coder` use surfaced a narrow set of real issues, not a
broad redesign. The worker is a *faithful implementer* — keep it narrow:
implement the brief, then verify with a real **batch-mode compile** when the
Unity project isn't open (graceful warn when it can't run). The expensive failures are
**upstream** (bad-premise briefs), not the worker's to fix. The Pi rebuild leans
on the shipped `subagent` extension verbatim, adapts `worker.md` → `diff-coder.md`,
adds a **structured single-diff brief contract**, and trims worker output to
**terse-by-default with conditional assumption surfacing**. Proactive delegation
is on (orchestrator decides), made cost-observable via the extension's usage
render.

## Out of scope

- The Claude Code `diff-coder` (reference only) and any harness-agnostic shared contract.
- `diff-reviewer` redesign (its own retro).
- The `subagent` extension's internals — we consume it as-is.

## Retro findings

Walked five questions; each resolved to a design implication.

### Q1 — Escalation behavior `RESOLVED`

Not load-bearing. Escalation rarely mattered because briefs are well-spec'd and
the **orchestrator-driven loop self-heals**: the main thread sees compile/test
failures or diff-reviewer findings and either fixes them in-place or
re-delegates. The worker never compiled/tested itself (contract held — no drift).

**Implication:** keep the escalate-without-implementing tiers as *cheap
insurance*; do not redesign around them. The real safety net is the outer loop.
*Pi consequence:* the `subagent` extension cold-spawns a fresh `pi -p` process
per call, so workers are **stateless across iterations** — the orchestrator
carries full context (original brief + prior diff + failure) into each re-brief.
The fix-vs-re-delegate decision is an **orchestration concern**, not the worker's.

### Q2 — Sonnet quality / rework rate `RESOLVED`

Diffs usually don't need heavy rework — the cost arbitrage holds. Two real
issues:

- **Compile-misses (common, minor):** "sometimes they don't compile." Syntax/type
  errors escape to the orchestrator because the worker doesn't build.
- **Significant rework (rare, expensive):** root cause is a **wrong assumption in
  the brief** — a user/orchestrator error upstream, *not* a worker fault.

**Implications:**
- **Worker runs real verification tooling** (not LLM self-fact-checking),
  best-effort, via the brief's `Verify` commands:
  - **Compile is the concrete path (spike-verified, Diff 3):** `Unity -batchmode
    -nographics -quit -projectPath <p> -logFile <log>` compiles C# headlessly (no
    display). Errors surface **both ways**: non-zero exit (`1`, with "Aborting
    batchmode due to failure: Scripts have compiler errors.") **and** parseable
    `path(line,col): error CS####: …` lines in the log — so the worker both
    *detects* (exit code) and *fixes* (log). Timing on XRHandsSample: ~35s cold,
    **~8s warm**. Needs **exclusive** project access → run only when the Editor
    isn't holding the lock. **Open-Editor signal (Diff 6-refined):** check
    `<project>/Library/EditorInstance.json` (a live Editor maintains it; absent ⇒
    safe to compile). `Temp/UnityLockfile` *alone* is unreliable — a 0-byte marker
    that **unclean exits leave stale** (Diff 6 hit exactly this: a stale lock from
    an aborted batch run false-blocked the trial until cleared). Prefer
    `EditorInstance.json`, or combine with a live-process check. License coexists
    with a running Editor (concurrent batch OK). *Expect the warn-path to be common
    during active dev.*
  - **Lint/format is an open question.** `eclint` (editorconfig) and
    `clang-format` exist but are formatting-only, and clang-format is mostly the
    C++ native side; whether a *C# semantic* linter/analyzer runs headless under
    Unity is unknown. Treat lint as opportunistic, not a guaranteed tier.
  - **Bounded self-fix:** on compile errors, fix what you introduced and re-run
    (cap ~2 retries).
  - **Three terminal states:** clean → success; can't-run → success + UNVERIFIED
    warning; still-failing-after-retries → report errors (not success).
  - Justifies `bash` in the worker toolset; shifts the contract from "does not
    compile/test" to "runs compile/lint + bounded fix; tests stay upstream."
  *(`dotnet format` against the Unity-generated csproj is the candidate to
  investigate for C# lint — see the Open questions DQ.)*
- Bad-premise briefs are an **upstream fix** (premise validation at brief-
  authoring time — already the "Validate Premises Before Designing" rule). **Not**
  a worker contract change. Keep only the existing *passive* conflicting-state
  escalation (if the worker trips over a contradiction while implementing — the
  type it's told to extend doesn't exist — it bails instead of hallucinating).
- **Boundary clarified:** worker = faithful implementer + best-effort mechanical
  verification (compile/lint); semantic correctness (tests, review) and *what* to
  implement = upstream.

### Q3 — Brief sufficiency `RESOLVED`

The brief is **orchestrator-generated and was never inspected** ("never opened
that black box"); it "may even just pass the diff plan." A worker handed the
whole plan can over-implement (it can't see the conversation — the plan text is
its entire world).

**Implication — structured brief contract (option b):** the orchestrator fills a
lightweight schema *projected from* the diff plan — the plan is the source, the
brief is a one-diff projection. **Instruction-enforced** (the subagent tool's
`task` stays a free string; structure comes from the template, not a forked tool
schema). Inspectable for free via the Pi tool call + session log. No mandatory
user review gate — orchestrator stays author; user can glance when something
smells off.

Brief fields:
- **Scope / description** — what this one diff does.
- **Files to touch** — explicit list.
- **Acceptance criteria** — what "done" means.
- **Pattern references** — `file.cs:line` to mirror.
- **Out-of-scope / don't-touch** — explicit guard against over-implementation.
- **Verify** — compile/lint commands to run (lock-free lint always; compile best-effort). Absent → worker reports unverified.

### Q4 — Proactivity `RESOLVED`

Under Claude Code the orchestrator *did* delegate proactively after the May flip,
but there was **no way to know whether a delegation was worth the spin-up**.

**Implication — instructed-proactive:** the orchestrator decides when to delegate,
with a **cost-aware threshold** — delegate substantial / multi-file /
pattern-following diffs; keep one-or-two-line and exploratory work in-thread.
The rule is injected **orchestrator-only** via a `tui`-gated `before_agent_start`
extension (**Route Y**), not placed statically in `APPEND_SYSTEM.md` — so the
spawned worker (mode `json`/`print`) never inherits it. The stale single-agent
stance is stripped from `APPEND_SYSTEM.md` so neither side is misinformed.
(Fuller worker-context isolation — `--no-context-files` / separate
`PI_CODING_AGENT_DIR` on the spawn, "Route X" — remains available since the
extension is vendored, but isn't needed for the delegation rule.)

Pi splits the "worth it?" concern in two:
- **Seeing the cost** — solved now, free: the `subagent` extension renders
  per-delegation **usage (turns, tokens, $cost, model)** in the tool result.
- **Reducing the cost** — the deferred warm-worker / IPC idea; lowers the
  threshold later.

### Q5 — Worker output `RESOLVED`

The `Files changed` + `Key decisions` output was **never read — noise and wasted
tokens**.

**Implication — terse-by-default, conditional surfacing** (the worker inheriting
the user's own output philosophy):
- **Drop `Files changed`** — redundant with the orchestrator's `git diff` and
  Pi's rendered edits.
- **Drop the always-on `Key decisions`** boilerplate.
- **Keep a terse completion line by default; surface assumptions *only when* the
  worker had to fill a gap the brief left open.** Happy path → no assumptions
  section → no wasted tokens. Thin-brief path → one line flagging the guess, so
  the orchestrator/user can catch a wrong-premise diff before accepting. This is
  the cheap, passive version of the escalation we declined to build.

## Consolidated decisions

| # | Decision | Resolution |
|---|----------|-----------|
| D1 | Scope | **Pi-only.** Claude `diff-coder` is reference, not maintained. |
| D-build | Starting point | **Lean on the shipped `subagent` extension verbatim**; adapt `worker.md` → `diff-coder.md`. "Start somewhere." |
| Q1 | Escalation | Cheap insurance only; safety net is the orchestrator loop. Workers stateless across cold-spawns → fat re-briefs. |
| Q2 | Quality | Worker **runs real compile/lint tooling** (best-effort, bounded self-fix; warn when it can't run); bad-premise briefs fixed **upstream**. Keep passive conflicting-state escalation. |
| Q3 | Brief | **Structured single-diff projection (option b)**, instruction-enforced, inspectable, orchestrator-authored, no mandatory gate. |
| Q4 | Proactivity | **Instructed-proactive**, cost-aware threshold; lean on the extension's usage render for observability. |
| Q5 | Output | **Terse by default + conditional assumption surfacing.** Drop `Files changed` and always-on `Key decisions`. |

## Dependency: the `subagent` mechanism

`diff-coder.md` is **inert on its own** — the spawn, the `agents/` discovery, the
brief delivery, and the usage render are all provided by the `subagent`
extension, not Pi core (Pi has no built-in subagents).

**Decision: vendor the first-party example to start.** Copy `index.ts` +
`agents.ts` from the Pi package's `examples/extensions/subagent/` into
`rybalt/pi/extensions/subagent/`, deploy to `~/.pi/agent/extensions/subagent/`
via `deploy.yaml` — same pattern as the existing `questionnaire.ts` / `scratch.ts`.
Only those two files are needed; the sample `agents/*.md` and chain `prompts/*.md`
presets are optional. Peer deps (`@earendil-works/*`, `typebox`) are resolved by
the Pi runtime at extension load, so location doesn't matter.

*Rationale:* the example is **first-party** (ships in the Pi package, maintained
by the Pi team) — high provenance, reviewed once, pinned, owned in the config
repo, no new trust decision. Trial-appropriate. Cost: manual upstream sync
(occasionally diff against the example for fixes). Do **not** symlink from the
homebrew/npm install path — `pi update --self` can replace it.

*Upgrade path (deferred):* the `pi-subagents` npm package family (`nicobailon`,
`@tintinweb`, `@gotgenes` forks; `pi install npm:pi-subagents@<pinned>`) is
maintained and gets fixes via `pi update`. Switch only if the manual-sync burden
bites, and only after: (1) source review — third-party packages run with full
system access (**trust inversion**: "more maintained" ≠ "safer" vs. the
first-party example), (2) confirming it uses the same `~/.pi/agent/agents/*.md` +
frontmatter convention so this design ports unchanged, (3) pinning a version +
picking a fork deliberately.

## Proposed `diff-coder.md` agent file (design sketch)

> **Pi has no first-class agents/subagents concept** — its design principles
> explicitly exclude built-in sub-agents. `~/.pi/agent/agents/` is **not** a Pi
> builtin path; it is a **convention owned by the `subagent` extension**, whose
> `agents.ts` reads `*.md` from `<agentDir>/agents/` (user) and `.pi/agents/`
> (project). The directory is inert unless that extension is installed. Our
> `diff-coder.md` lives there *because we install the extension*, not because Pi
> recognizes "agents."

Lives at `~/.pi/agent/agents/diff-coder.md` (deployed from rybalt). Frontmatter
per the `subagent` extension's `agents.ts` discovery (`examples/extensions/subagent/agents.ts` in the Pi package); body becomes the worker's appended system prompt.

```markdown
---
name: diff-coder
description: Implement a single scoped diff from a stacked-diff plan. Faithful implementer — verifies with available compile/lint tooling; does not run the test suite, stage, or commit.
model: claude-sonnet-4-5
tools: read, write, edit, bash, grep, find, ls
---

You implement exactly one diff, described in your prompt, and verify it with the
compile/lint tooling the brief provides. You do NOT run the full test suite,
stage, or commit — the orchestrator owns that loop.

## Expected input (brief)
You receive a single-diff brief: scope/description, files to touch, acceptance
criteria, pattern references (file:line), explicit out-of-scope, and a `Verify`
block of compile/lint commands. Implement only within that scope. Do not reach
into adjacent diffs or files not listed.

## Process
1. Read context first — the files you'll touch and any pattern references.
2. Implement the diff within scope.
3. Verify (best-effort), using the brief's `Verify` commands:
   - Run the compile command if given and the project is free (no Unity editor
     lock). On errors, fix what you introduced and re-run, up to 2 retries.
   - Run any lint/format commands if given (opportunistic).
   - Terminal states: **clean** → success; **can't run** (no command, editor
     lock, tool missing) → success + a one-line UNVERIFIED warning; **still
     failing after retries** → report the errors; do NOT claim success.
4. Return per Output, below.

## Escalation (cheap insurance — passive only)
If, while implementing, you hit a contradiction with the brief (a type you're
told to extend doesn't exist; a signature doesn't match), STOP and return the
contradiction instead of inventing your way past it. Do not proactively
re-validate the brief's premises — that is the orchestrator's job.

## Output (terse by default)
- One line: what you implemented + verification status (compiled & lint clean /
  lint clean, compile UNVERIFIED / compile FAILED).
- ONLY IF you had to fill a gap the brief left open: one line per assumption.
- ONLY IF compile FAILED after retries: the errors.
- Nothing else. No file list (the orchestrator runs its own diff).
```

Status `proposed` — exact wording is a build-time concern, gated on sign-off.

## Brief template (orchestrator-side)

The orchestrator fills this when calling the `subagent` tool (`task` arg):

```
Diff: <name/number> — <one-line scope>
Files: <explicit list>
Acceptance: <what "done" means>
Patterns: <file.cs:line references to mirror>
Out of scope: <what NOT to touch>
Verify: <lint/compile commands to run; omit → worker reports unverified>
```

To be documented in `APPEND_SYSTEM.md` / `AGENTS.md` as the delegation default.

## Deferred — future considerations

1. **Persistent worker + IPC tunnel** (`pi --mode rpc`) vs. cold-spawn-per-call —
   warm context across inner-loop iterations; lowers the re-delegate / proactive
   threshold. The user's primary motivation; the biggest deferred item.
2. **A fast, lock-free C# compile path** so worker compile-verify is the *common*
   path, not the exception. Warm Unity batch-mode is only ~8s (Diff 3), so speed
   isn't the blocker — the **editor lock** is: it's unavailable while the Editor is
   open, so the worker falls back to the UNVERIFIED warning during active dev. A
   `dotnet build` against a synced solution is the candidate lock-free path.
3. **Schema-enforced brief** (modify the extension's tool params) if instruction-
   enforcement drifts.
4. **Heavier telemetry** (rework-rate vs. cost per delegation) if the usage-render
   floor proves insufficient.
5. **Code-convention enforcement** in delegated diffs — workers don't reliably
   follow or self-report style; the robust fix is a formatter in the `Verify`
   step, gated on the headless-C#-format path (#2). IOU:
   `~/pkm/inbox/diff-coder-convention-enforcement-iou.md`.

## Open questions & next steps

### DQ: Does the structured brief match what the orchestrator actually produces? `RESOLVED`
Diff 6 trial: the orchestrator composed a template-conforming brief (all six
fields) and delegated it cleanly end-to-end — implement → real Unity compile-verify
(exit 0) → orchestrator review. Template validated against a real delegation.

### DQ: Does any C# lint/analyzer run headless under Unity? `RESOLVED`
Spike (Diff 3) outcome: the **Unity batch-mode compile** is the reliable headless
C# verification (exit code + parseable `error CS####`). A separate headless C#
*lint* is **not** a quick win — `-batchmode -quit` doesn't emit IDE `.csproj`, so
`dotnet build`/`format` (dotnet 10 is installed) needs a solution-sync step first
plus Unity-specific reference/define handling; left as the deferred "fast,
lock-free compile path." `eclint`/`clang-format` remain editorconfig/native-only.
`Temp/UnityLockfile` open-Editor signal **confirmed** (present/absent; stale-safe).

### Next steps (build, gated on sign-off)
1. **Vendor** the `subagent` example: copy `index.ts` + `agents.ts` into `rybalt/pi/extensions/subagent/`; deploy to `~/.pi/agent/extensions/subagent/` via `deploy.yaml`. (Do not symlink from the Pi install path.)
2. Author `diff-coder.md` from the sketch above into `~/.pi/agent/agents/` (deployed from rybalt).
3. Add the brief template + cost-aware delegation default to `APPEND_SYSTEM.md` / `AGENTS.md`.
4. Trial on a real stacked diff; capture the brief (DQ above); iterate.
