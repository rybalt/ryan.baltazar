# diff-coder — Implementation Plan

Execution plan for the Pi diff-coder designed in
[diff-coder-retro-and-design.md](./diff-coder-retro-and-design.md). Stacked
diffs, each self-contained and sign-off-gated. User stages and commits.

**Status:** complete (2026-06-10) — all 6 diffs signed off.
**Deploy model:** `deploy/deploy.py` symlinks per `pi/deploy.yaml`. `extensions/`
and `APPEND_SYSTEM.md` are already linked; `agents/` is **not** (Diff 2 adds it).
During iteration, an extension can be loaded without deploying via
`pi -e ./pi/extensions/subagent`.

## Diff order & rationale

Harness-only work first (Diffs 1–2 — no Unity needed, fast to test), then the
Unity-gated verification spike (Diff 3). Orchestrator enablement is split per
**Route Y**: Diff 4 strips the stale single-agent stance from `APPEND_SYSTEM.md`
(+ the project verify command), and Diff 5 adds a `tui`-gated extension that
injects the active delegation rule into the interactive orchestrator only — never
the workers. Diff 6 is an end-to-end trial. The spike is deliberately *after* the
mechanism because the agent's verify behavior is generic ("run the command the
brief gives"); only the *concrete* command depends on the spike.

---

## Diff 1 — Vendor the `subagent` extension

**Scope:** bring the first-party `subagent` example into the repo as the
delegation mechanism. No behavior authored yet.

**Files:**
- `pi/extensions/subagent/index.ts` (copied verbatim from the Pi package's `examples/extensions/subagent/index.ts`)
- `pi/extensions/subagent/agents.ts` (copied verbatim)

No `deploy.yaml` change — `extensions/` is already a whole-dir symlink, so the
subdir deploys automatically.

**Acceptance criteria:**
- Extension loads with no error; `subagent` tool is registered.
- Invoking `subagent` with a bogus agent name returns the graceful "unknown
  agent — available: none" path (no agents authored yet).

**Test plan:**
- `pi -e ./pi/extensions/subagent -p "use the subagent tool with agent 'nope' and task 'noop'"` → returns the unknown-agent message, exits clean.
- Confirm the startup header / tool list includes `subagent`.

(Vendored code — doesn't count against the diff line budget.)

### Sign-off
- [ ] Extension loads, tool registered
- [ ] Graceful unknown-agent path verified
- [ ] User sign-off

---

## Diff 2 — `agents/` deploy link + author `diff-coder.md`

**Scope:** create the agent definition and make it deployable.

**Files:**
- `pi/agents/diff-coder.md` (from the design doc's sketch, finalized)
- `pi/deploy.yaml` — add:
  ```yaml
  - source: agents
    target: ~/.pi/agent/agents
  ```

**Acceptance criteria:**
- After deploy (or via a scratch project `.pi/agents/`), `subagent` lists `diff-coder` as an available agent.
- A trivial delegation runs end-to-end: worker implements within scope, returns the terse one-line output.
- All three verification terminal states are reachable.

**Test plan (harness-only — no Unity):**
- Delegate `{agent: "diff-coder", task: <create a small file mirroring a given pattern>, Verify: omitted}` → worker writes the file, returns `…; compile UNVERIFIED`.
- Same with `Verify: true` (dummy pass) → `…; verified`.
- Same with `Verify: false` (forced fail) → reports FAILED, does not claim success.
- Confirm output has no `Files changed` block and no assumptions line on a fully-specified brief.

### Sign-off
- [ ] `diff-coder` discovered by `subagent`
- [ ] End-to-end trivial delegation writes files + terse output
- [ ] Three verification states (clean / UNVERIFIED / FAILED) observed
- [ ] Output contract honored (no file list; conditional assumptions)
- [ ] User sign-off

---

## Diff 3 — Verification feasibility spike (Unity-gated)

**Scope:** resolve the two `OPEN` DQs in the design doc. Disposable
investigation; the only artifact is updated design-doc findings.

**Investigate:**
- Exact headless C# compile invocation for a test project (e.g. `CIProject-Unity6`): `Unity -batchmode -quit -projectPath <p> -logFile -` and how CS errors surface / are parsed.
- `Temp/UnityLockfile` presence as the open-Editor signal (present with Editor open, absent when closed).
- Whether any C# lint runs headless (`dotnet format` against the Unity-generated `.csproj`?).

**Acceptance criteria:**
- A documented, working compile command that surfaces a deliberately-introduced CS error.
- Confirmed (or rejected) lockfile-detection signal, with the alternative if rejected.
- A yes/no on headless C# lint, with the command if yes.

**Test plan:**
- Editor closed → run the compile command on a project with a planted `CS#### ` error → error appears in the log; on clean tree → exits 0.
- Editor open → confirm `Temp/UnityLockfile` exists; closed → gone.

**Outcome:** update [diff-coder-retro-and-design.md](./diff-coder-retro-and-design.md) — flip the two DQs to `RESOLVED`/`WONTFIX`, record the concrete command(s).

### Sign-off
- [x] Working headless compile command documented (`-batchmode -nographics -quit`; exit code + `error CS` log lines; ~8s warm / ~35s cold)
- [x] Lockfile detection confirmed (`Temp/UnityLockfile`, stale-safe)
- [x] C# lint determination recorded (no quick headless lint; compile is the check; `dotnet` path deferred)
- [x] Design-doc DQs updated (both flipped to `RESOLVED`)
- [ ] User sign-off

---

## Diff 4 — Strip the single-agent stance (`APPEND_SYSTEM.md`) + verify command (project `AGENTS.md`)

**Scope:** make the orchestrator *delegation-neutral* and stop misinforming the
worker. Under Route Y the **active** delegation rule lives in a `tui`-gated
extension (Diff 5), so here we only **remove** the stale prohibition and add the
project-side verify reference. Leaving the rule out of `APPEND_SYSTEM.md` is the
whole point — that file loads in the worker too.

**Files:**
- `pi/APPEND_SYSTEM.md` (rybalt) — remove/soften the "no subagents… do the work in
  one loop" + "ignore delegation sections" language. After this, neither the
  orchestrator nor the worker reads a stale "don't delegate." Do **not** add the
  active delegation rule here (that's Diff 5, orchestrator-only).
- `CSharpMockRuntime_Hackweek2026/AGENTS.md` (**separate repo** — the workspace) —
  add/point to the concrete headless-compile command (from Diff 3) as the
  `Verify` value. Likely a one-line pointer; the build recipes already live there.

**Acceptance criteria:**
- No surviving text in `APPEND_SYSTEM.md` that prohibits or contradicts delegation.
- A spawned worker no longer inherits a "don't delegate" / "one loop" instruction.
- Project `AGENTS.md` carries the concrete verify command.

**Test plan:**
- Re-read `APPEND_SYSTEM.md`: the single-agent stance is gone, and nothing
  references diff-coder yet (the rule arrives in Diff 5).
- Confirm a worker's effective context no longer contains "do the work in one loop."

**Note:** touches two repos (rybalt + the workspace). Stage/commit separately.

### Sign-off
- [ ] Single-agent/no-delegation stance removed from `APPEND_SYSTEM.md`
- [ ] No active delegation rule added here (deferred to Diff 5)
- [ ] Verify command in project `AGENTS.md`
- [ ] User sign-off

---

## Diff 5 — `tui`-gated delegation-rules extension (Route Y)

**Scope:** inject the active delegation rule (cost-aware threshold + brief
template) into the **orchestrator's** system prompt only, so workers never see
it. The clean home for orchestrator-only behavior.

**Files:**
- `pi/extensions/orchestrator-rules/index.ts` — a `before_agent_start` hook that
  returns `{ systemPrompt: event.systemPrompt + RULES }` **only when**
  `ctx.mode === "tui"`. Deploys via the already-linked `extensions/` dir.
- `pi/extensions/orchestrator-rules/delegation-rules.md` — the rule prose (brief
  template + threshold), read by the extension so the content stays editable
  markdown rather than a TS string literal.

**Mechanism (confirmed in `docs/extensions.md`):** `before_agent_start` can modify
the system prompt; `ctx.mode ∈ {tui, rpc, json, print}`; the worker spawns with
`--mode json -p`, so `ctx.mode !== "tui"` for workers. Net: the rule lands in the
interactive orchestrator, absent from every subagent.

**Acceptance criteria:**
- Interactive (`tui`) system prompt contains the delegation rule + brief template.
- A subagent worker (mode `json`/`print`) system prompt does **not** contain it.
- The orchestrator delegates a substantial diff with a template-conforming brief.

**Test plan:**
- Interactive: probe `ctx.getSystemPrompt()` (or the `system-prompt-header` example's
  length check / a debug log) — rule present in `tui`.
- Worker: run a delegation and confirm the worker's effective prompt lacks the rule
  (temporary worker-prompt log, or assert no delegation attempt — it lacks the
  `subagent` tool regardless).
- Dry delegation: 2-diff plan → orchestrator delegates the substantial diff; brief
  matches the template (closes the brief-match DQ).

### Sign-off
- [x] Absent in worker (`json`) — probe-confirmed; `tui`-injection by inspection (rules file loads; guard identical to `pirate.ts`) + live confirm on `/reload`
- [~] Dry-run delegation produces a template-conforming brief — folds into Diff 6 (needs a live `tui` delegation)
- [ ] User sign-off

---

## Diff 6 — End-to-end trial + close brief DQ

**Scope:** run one real stacked-diff feature through diff-coder; validate the
economics and the brief template against reality.

**Acceptance criteria:**
- One real diff implemented via `diff-coder` end-to-end (delegate → verify → orchestrator review → sign-off).
- Per-delegation usage (cost/turns/tokens) observed via the extension render.
- The captured `task` arg validated against the template; design-doc brief DQ resolved or iterated.

**Test plan:**
- Pick a small real mock-runtime diff; run the full loop with the Editor closed (so compile-verify actually fires at least once).
- Record: did it compile clean? rework needed? cost vs. an inline estimate?
- Capture the brief; update the brief-match DQ.

### Sign-off
- [x] Real diff delivered via diff-coder (`RybaltHelloWorld.cs`, exact marker, compile-verify exit 0)
- [x] Usage/cost observed — rendered in the TUI subagent tool card; confirmed working
- [x] Brief DQ resolved; design doc updated (+ lockfile-guard refinement → `EditorInstance.json`)
- [x] User sign-off

---

## Not in this plan

- Deferred items from the design doc (warm-worker/IPC, fast lock-free compile path, schema-enforced brief, heavier telemetry) — revisit after the trial.
- `diff-reviewer` port and any implement→review chain composition.
- Migrating to the `pi-subagents` npm package (upgrade path, gated on source review).
