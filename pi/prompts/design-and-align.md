---
description: Enter a design-and-align loop — explore the problem and align on decisions before producing any artifact
argument-hint: "[topic or problem statement]"
---
Enter **design-and-align mode** for: $@

(If no topic was given above, use the current conversation as the subject.)

This is a collaborative design discussion, **not** an execution request. Your
job in this mode is to think *with* me and reach explicit alignment before
anything is built. Until I say to proceed, treat this as **read-only**: explore,
read code/docs, and discuss — do **not** write plan documents, create files, or
edit code. The one exception is an explicitly-labeled, disposable **spike** to
de-risk a design question — and only after you ask permission for it first.

**First-write tripwire:** before your *first* file write or edit of any kind,
stop and ask for an explicit go — even if you believe alignment is already
reached.

Work through these steps, pausing for my input rather than racing to the end:

1. **Restate the problem.** Reflect the goal and scope back in your own words so
   we confirm we're solving the same thing. Note what's explicitly out of scope.
2. **Map the problem space.** Gather context: read relevant code, and check for
   prior art (PKM at `~/pkm`, project `docs/`, existing tools/packages) before
   reasoning from scratch. Summarize what already exists.
3. **Enumerate requirements.** List functional and non-functional requirements,
   separated into **must / should / nice-to-have**. Flag any you're inferring
   rather than ones I stated.
4. **Surface ambiguities as explicit decisions.** This is the core of the loop.
   Front-load only the **blocking / high-impact** decisions; defer
   bikeshed-level ones to build time. For each, present a numbered decision with:
   the options, their tradeoffs, and your lean (with reasoning). **Do not
   resolve ambiguity unilaterally** — put the choice in front of me.
5. **Align (and log).** Stop and let me weigh in. Iterate on the decisions,
   requirements, and scope until we converge — expect multiple rounds. Each
   round, restate a running **"Decisions so far"** summary so resolved choices
   survive and seed the artifact's rationale.
6. **Reach "aligned," then ask for go.** Aligned = every surfaced decision is
   resolved or explicitly deferred. At that point, summarize and ask for an
   explicit go — do not start building on your own read of consensus. Only after
   I approve, produce the artifact (plan doc, code, etc.), confirming *where* it
   should live before writing it.

Anti-patterns to avoid (these are why this mode exists):
- Jumping straight to a finished plan doc or implementation.
- Picking answers for ambiguous decisions and baking them into an artifact.
- Treating "let's plan X" or "let's go to the plan" as "produce the plan now."

Begin with steps 1–4. Then stop and wait for me.
