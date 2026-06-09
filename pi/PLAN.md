# Pi Transition Plan

Evaluation and hackweek-trial plan for adopting the [Pi](https://pi.dev/) coding
agent harness alongside Claude Code.

**Status:** trial / experiment (started 2026-06-08). Low commitment.
**Goal direction:** a permanent two-harness split, validated via a hackweek
building minor features into the OpenXR mock runtime in `HandExtensibility`.
**Mode:** single-agent on Pi (no subagent fan-out).

---

## TL;DR

Pi is a deliberately minimal harness: four core tools (read/write/edit/bash +
grep/find/ls), a bare ReAct loop, and **no built-in subagents, plan mode,
permission gates, MCP, or to-dos** — you add those via extensions/packages or
rely on external tools. That design is the opposite of where this user's Claude
Code setup invests (delegation, gated dev loop, `unity-mcp`).

The trial deliberately **drops** the multi-agent machinery rather than porting
it, which collapses the migration cost to near zero. The mock-runtime dev loop
is fully CLI-drivable (`./bee` + Unity CLI test recipes), so **no MCP adapter is
needed** for the hackweek.

## The split

| Lane | Harness | Why |
|---|---|---|
| Mock-runtime feature work (the hackweek), config/scripting edits, greenfield | **Pi** | CLI build/test loop; lightweight edits — squarely in Pi's core. Single-agent diff stack. |
| Large-codebase exploration; any future big feature wanting the full multi-agent dev loop | **Claude Code** | The `Explore` fan-out and `diff-coder`/`diff-reviewer`/`unity-editor` delegation have no Pi equivalent without building one. |

Note this is roughly the *reverse* of the naive "Pi for day-to-day, Claude Code
for exploration" instinct: exploration is the most Pi-friendly surface (read/grep
only), while the heavy delegated dev loop is the most Pi-hostile. The split above
optimizes for lowest porting cost during the trial.

## Architecture gap (Pi vs. this Claude Code setup)

| Claude Code asset | Pi story | Trial decision |
|---|---|---|
| `diff-coder` / `diff-reviewer` / `unity-editor` subagents + delegation model | No native subagents (community extensions exist) | **Drop** — single-agent loop |
| Gated dev loop, sign-off checklists, auto-proceed/auto-loop trial flags | No plan mode / permission gates / to-dos | **Simplify** — keep manual sign-off; drop autonomy trials |
| `unity-mcp` | No native MCP; needs `pi-mcp-adapter` | **Defer** — CLI build/test covers the loop |
| Permission allowlists (`.claude/settings.local.json`) | No permission model at all | **Accept ungated bash** for the trial (see security note) |
| 7 skills (`diff-review`, `classify-changes`, `gen-openxr-native-types`, …) | First-class lazy skills | **Port the useful ones** (format TBD) |
| `claude/CLAUDE_home.md` (global prefs) | `APPEND_SYSTEM.md` | **Ported** → `pi/APPEND_SYSTEM.md` |
| `HandExtensibility/CLAUDE.md` (project) | `AGENTS.md` (already used in this repo) | **Augmented** existing root `AGENTS.md` additively |

## Artifacts produced

- [`pi/APPEND_SYSTEM.md`](APPEND_SYSTEM.md) — global prefs ported from
  `claude/CLAUDE_home.md`, minus the delegation/subagent model. Symlink target:
  `~/.pi/agent/APPEND_SYSTEM.md`.
- `HandExtensibility/AGENTS.md` — augmented additively with CLI build/test
  recipes (incl. the no-`-batchmode` mock-runtime path), formatting, coding
  conventions, threading assumption, productization workflow, and Review Noise.
  The pre-existing terse content and the rich `xr.sdk.openxr/AGENTS.md` were left
  intact. Diff-size guideline reconciled to 300-500 (per `CLAUDE.md`).

## Phase 0 — setup

Installs/auth are user-run (per the brew/git guardrail); config files are
already drafted.

1. **Install Pi** (user): per pi.dev/docs/latest — e.g. the official package, then
   authenticate one provider (Anthropic; keep Opus). Run a read-only smoke test
   before any edits.
2. **Wire global prefs** (user): symlink `~/.config/rybalt/pi/APPEND_SYSTEM.md`
   → `~/.pi/agent/APPEND_SYSTEM.md`. (Mirror of the `claude/CLAUDE_home.md`
   wiring; not yet a `deploy.py` module — no `pi/deploy.yaml` exists, so it won't
   auto-deploy. Add one later if the trial sticks.)
3. **Project instructions:** none needed — Pi reads `HandExtensibility/AGENTS.md`
   (augmented) and `xr.sdk.openxr/AGENTS.md` automatically. **Caveat:** Pi also
   loads `CLAUDE.md` as a context file and concatenates both, so the full
   `HandExtensibility/CLAUDE.md` (incl. the dropped subagent/autonomy content)
   loads too. `APPEND_SYSTEM.md` has higher authority and overrides those stale
   sections; the cost is duplicated context. See the dedup DQ below.
4. **Skills** (user): port the single-agent-useful skills into
   `~/.pi/agent/skills/`. Start with `diff-review` and `classify-changes`;
   add `gen-openxr-native-types` if the features touch interop types. Skip
   `unity-editor` (replaced by CLI), `session-*` and `project-bootstrap`
   (PKM/MCP-coupled — defer). See DQ on skill format below before bulk-porting.
5. **No MCP** for the trial. CLI build/test only.

**Security note:** Pi has *no permission gates* — `bash` runs ungated, so the
`.claude/settings.local.json` allowlists do not translate. Acceptable for a
hackweek in a trusted repo; a sandboxing extension exists if needed later.

## Phase 1 — the work (mock-runtime features)

Run as a stacked diff, single-agent, per the dev loop in `pi/APPEND_SYSTEM.md`:
edit → `./bee` (only if native changed) → CLI test (use the no-`-batchmode`
recipe for mock-runtime PlayMode) → inline `diff-review` → show diff + verdict →
**user signs off** → next diff. User stages and commits.

## Phase 2 — evaluate (post-hackweek)

Decide whether the two-harness split becomes permanent.

- Did single-agent Pi hold up for diff-stack work, or did the missing
  reviewer/orchestrator fan-out hurt (context bloat, lost review rigor)?
- Did ungated bash cause any near-misses (would a permission model have helped)?
- How painful was the CLI test loop vs. the `unity-editor` MCP convenience?
- Did the skills port cleanly, or is the format friction high?

If positive: formalize the split, add a `pi/deploy.yaml` module, port more
skills, and revisit whether the multi-agent dev loop is worth rebuilding as Pi
extensions.

## Open questions

### DQ: Are Claude Code `SKILL.md` files directly usable as Pi skills? `OPEN`

Pi skills are "capability packages with instructions and tools, loaded
on-demand." Claude Code skills are `SKILL.md` + frontmatter. Unknown whether
Pi consumes them as-is or needs a manifest/wrapper. Validate by porting one
simple skill (`classify-changes`) first. `skill.sh` is the universal installer
for published skills; local custom skills likely just copy/symlink into
`~/.pi/agent/skills/`.

### DQ: When (if ever) to add `pi-mcp-adapter` for `unity-mcp`? `OPEN`

Only if editor-in-the-loop compile/test proves materially better than the CLI
recipes during the trial. The adapter proxies MCP via a ~200-token tool to
preserve Pi's lazy-loading, and Pi can import the existing `.mcp.json` via its
claude-code config import. Deferred for now.

### DQ: Dedup the AGENTS.md / CLAUDE.md co-load for Pi? `OPEN`

Pi concatenates *both* `AGENTS.md` and `CLAUDE.md` from a directory ("All
matching files are concatenated"), with no built-in way to ignore one. So in
`HandExtensibility`, Pi loads the augmented `AGENTS.md` **and** the full 640-line
`CLAUDE.md` — duplicating the recipes and pulling in the subagent/autonomy
content the single-agent trial dropped. Mitigations considered: renaming/removing
`CLAUDE.md` (breaks Claude Code — rejected); `--no-context-files` (kills
`AGENTS.md` too — rejected); a custom Pi extension to filter (Phase 2+).
**Trial decision:** keep both; `APPEND_SYSTEM.md` (higher authority) overrides
the stale `CLAUDE.md` sections; tolerate the token duplication. The augmented
`AGENTS.md` still earns its keep for `AGENTS.md`-only harnesses (Codex) that
don't read `CLAUDE.md`. Phase 2: decide whether to slim `CLAUDE.md` to defer to
`AGENTS.md` (or vice versa) once the harness split is settled.

### DQ: Reconcile diff-size guidance across CLAUDE.md / AGENTS.md? `RESOLVED`

Authoritative value is **300-500 lines of significant code** (per `CLAUDE.md`).
Root `AGENTS.md` updated from its prior "~200" to match.

## Sources

- [Pi Coding Agent](https://pi.dev/) — official site/docs.
- [Pi: The Minimal Agent Within OpenClaw](https://lucumr.pocoo.org/2026/1/31/pi/)
  — Armin Ronacher on the design (no MCP/subagents by design; lazy skills).
- [Pi Review 2026 — vibecodinghub](https://vibecodinghub.org/tools/pi).
- `pi-mcp-adapter` — github.com/nicobailon/pi-mcp-adapter (MCP via ~200-token proxy).
- `awesome-pi-agent` — github.com/qualisero/awesome-pi-agent.
