---
name: session-wrap
description: Summarize session learnings, decisions, and WIP state into PKM journal entries, update topic-specific notes, and generate a continuation prompt for the next session. Use at the end of a work session or when switching contexts.
---

# Session Wrap

Wrap up the current session by extracting significant context and persisting it to the PKM system. Optional arguments: `$ARGUMENTS` can contain topic hints or note paths to focus the scan (e.g., `AXRB-44 com.unity.xr.hands`). If no arguments are provided, scan the full conversation.

**PKM root:** `~/pkm` (the symlink to your PKM repo — the directory containing `_manifest.json`). Under Pi you typically run from a *code* project, not the PKM itself, so always reference PKM paths by absolute path under `~/pkm`, not the current working directory. All relative paths below (`journal/`, `tickets/`, `_scripts/`, …) are relative to `~/pkm`.

## Phase 1: Scan & Detect Topics

Scan the conversation history for significant topics. Look for:

- **Ticket IDs** — Jira-style IDs (e.g., `AXRB-44`, `UUM-72628`). Match to `tickets/<ID>*.md` or `tickets/<ID>/` in the PKM. Ticket IDs are NOT reliably present in branch names. Detect them from: explicit mentions in the conversation, PR titles/bodies (query with `gh pr view`), or ask the user if the session involved ticket-driven work but no ID was mentioned.
- **Pull requests** — PRs created, reviewed, or referenced during the session. Detect from `gh pr` commands, PR URLs, or `owner/repo#NNN` references. Use `gh pr view <number> --repo <owner/repo> --json number,title,url,state,headRefName,baseRefName,body` to fetch current metadata for each detected PR.
- **Package names** — `com.unity.*` references. Match to `packages/<package-name>/` subdirs.
- **Explicit note references** — File paths or note names mentioned in the conversation. Match to any PKM note.
- **Design topics** — Architecture decisions, ADR discussions. Match to `design/` notes.
- **Unmatched topics** — Significant discussion threads that don't map to existing PKM notes. Flag these separately.

If `$ARGUMENTS` contains topic hints, prioritize those but still scan for additional topics.

For each detected topic, extract seven categories of information:

1. **Decisions & rationale** — Conclusions reached, design questions resolved, approach chosen and why alternatives were rejected.
2. **Discovered facts** — Things learned about codebases, APIs, specs, or runtime behavior that would require re-investigation in a fresh session.
3. **WIP state** — What's in progress, what's blocked, unfinished threads, errors not yet resolved.
4. **Artifacts** — Files created/modified, PRs opened, branches created, commits made.
5. **Branch state** — For each active branch: does it compile, do tests pass, does it need rebasing onto another branch, what commit is it at.
6. **Known issues** — Things that are broken and known about. Compile errors on branches that haven't been rebased, stale API calls after refactors, test failures that need addressing.
7. **User-modified files** — Files the user edited directly (outside of agent tool calls) during the session. These may differ from what the agent last read and should be re-read in the next session.

Read `~/pkm/_manifest.json` to match detected topics against existing PKM notes.

## Phase 2: Confirm Targets

Present the detected topics to the user for confirmation. Pi has no built-in
multi-select tool, so use whichever fits the session:

- **Default (no extra tooling):** print a numbered list of detected topics —
  each with its name/ID, the matched PKM note path (or "NEW — no existing note"),
  and a one-line summary — and ask the user to reply with any to **drop** and any
  to **add**. Include all detected topics unless the user deselects.
- **If the `questionnaire` extension is loaded:** you may instead ask one
  include/skip question per topic (it is single-select per question; there is no
  multi-select).

Example list:

```
Detected topics — reply with any to drop / add:
1. AXRB-44 — tickets/AXRB-44-hand-tracking.md — investigated joint data pipeline
2. com.unity.xr.hands — packages/com.unity.xr.hands/architecture.md — reviewed subsystem lifecycle
3. session-wrap skill (NEW) — no existing note — designed and built the skill
```

After confirmation, if any topic was marked "new note needed" and the user confirmed it, decide on the correct PKM location and filename following PKM naming rules. Do NOT create the new note yet — it will be created during Phase 4 if there is enough substance to warrant it.

## Phase 3: Write Journal Entry

**Target file:** `journal/YYYY-MM-DD.md` using **today's date**. NEVER
reuse a journal file from a previous date — even if session-begin loaded
an earlier entry, the wrap always creates or appends to today's file.
Sessions can span multiple days.

### If the file does NOT exist yet

Create it with this structure:

```markdown
---
title: "Session Log — YYYY-MM-DD"
created: YYYY-MM-DD
status: active
tags: [session-log]
---

# Session Log — YYYY-MM-DD

## Topic: <topic name>

**Related:** [note-name.md](../relative/path) | TICKET-ID | com.unity.package.name

### Decisions & Rationale
- Decision made, with reasoning

### Discovered Facts
- Fact learned that would need re-discovery

### Work in Progress
- What's in progress, blockers, unfinished threads

### Pull Requests
- [PR title](PR URL) — `owner/repo#NNN` — status, branch, one-line summary of what was done or reviewed

### Artifacts
- Files created/modified, branches created, commits made

### Branch State
- `branch-name` — compiles/broken, tests pass/fail, needs rebase onto X

### Known Issues
- Things that are broken and known about

### Next Steps
1. Concrete next action
2. Another concrete action

<!-- repeat ## Topic sections for each confirmed topic -->
```

### If the file ALREADY exists (multi-session day)

Read the existing file. Append new `## Topic` sections after the last topic section but before the `## Continuation Prompt` section (if one exists — remove the old continuation prompt section since it will be regenerated).

### Continuation prompt block

After all topic sections, append:

````markdown
## Continuation Prompt

```prompt
You are continuing a previous session. Here is the context you need:

<for each topic:>
## <topic name>
**Status:** <in-progress | blocked | completed>
**Related notes:** <list of PKM note paths to read>

<2-3 sentence summary of current state>

**Key decisions already made:**
- <decision — do not re-litigate>

**Open PRs:**
- [PR title](URL) — `owner/repo#NNN` on branch `branch-name` — <current status: draft/open/changes-requested/approved>

**Branch state:**
- `branch-name` — <compiles/broken>, <tests pass/fail>, <needs rebase onto X>
- <list each active branch with its current state>

**Known issues:**
- <things that are broken and known about — e.g. "040 still references AddFeature which was removed">
- <compile errors, test failures, or stale code that the next session needs to address>

**User-modified files:**
- <files the user edited directly in their editor that may differ from what the agent last saw — read these fresh>

**Next steps:**
1. <concrete action>

</for each topic>
```
````

### Style rules for journal entries

- Omit empty sections. If a topic has no "Discovered Facts", skip that heading entirely.
- Keep bullet points concise — one line each. Details belong in the topic-specific notes, not the journal.
- Use relative paths for all inter-note links (relative to `journal/`).
- The `Related:` line should link to the topic-specific PKM note if one exists, and include any ticket IDs or package names as plain text identifiers.

## Phase 4: Update Topic-Specific Notes

For each confirmed topic that maps to an existing PKM note:

### 4a: Merge into structured sections

Read the existing note. Make targeted updates:

- **Resolve DQs** — If the session resolved a design question marked `OPEN`, update its heading tag to `RESOLVED` and add a brief resolution summary below it.
- **Add new DQs** — If the session raised new open questions, add them as `### DQ: <question>? \`OPEN\`` headings.
- **Update frontmatter status** — If the note was `draft` and enough substance was added to consider it reviewed, update to `active`. Only do this if the session added significant, verified content.
- **Add new content sections** — If the session produced substantial new information that belongs in the note (not just a log entry), add it in the appropriate location within the note's existing structure.

### 4b: Append session log entry

Check if a `## Session Log` section exists at the bottom of the note.

**If it exists**, append a new dated subsection:

```markdown
### YYYY-MM-DD
- Brief summary of what was done/learned
- Key decisions or state changes
```

**If it does NOT exist**, create it:

```markdown
## Session Log

### YYYY-MM-DD
- Brief summary of what was done/learned
- Key decisions or state changes
```

### 4c: New notes for unmatched topics

For confirmed unmatched topics that warrant a new note:

- Create the note in the correct PKM directory with proper frontmatter
- Populate with the session's findings (not just a stub)
- Include a `## Session Log` section with today's entry

Only create a new note if there is genuine substance. A topic that was briefly mentioned but not deeply explored does not need its own note — the journal entry is sufficient.

## Phase 5: Write Continuation Prompt File

**Target directory:** `journal/_continuations/`
**Target file:** `journal/_continuations/YYYY-MM-DD.md`

If the file already exists (multi-session day), overwrite it with a merged
continuation that incorporates context from the existing file and the new
session. The continuation prompt should reflect the cumulative state across
all sessions that day — there is no value in keeping stale or duplicate
continuations.

Create the directory if it does not exist.

**Content:** The same continuation prompt text from the journal entry's fenced block, but as a standalone file with minimal frontmatter:

```markdown
---
title: "Continuation — YYYY-MM-DD"
created: YYYY-MM-DD
tags: [continuation]
---

<continuation prompt content — identical to the fenced block in the journal entry>
```

This file is designed to be piped into a new session (pi, Claude Code, etc.):
```
cat ~/pkm/journal/_continuations/YYYY-MM-DD.md
```

## Phase 6: Regenerate Manifest

Run the manifest generator from the PKM root:

```bash
cd ~/pkm && python3 _scripts/gen-manifest.py
```

Verify the script completes successfully. If it fails, report the error to the user.

## Post-Wrap Summary

After writing the journal and continuation files, do NOT repeat their contents in chat. The Post-Wrap Summary below is the only chat output for the wrap.

After all phases complete, present a brief summary:

```
Session wrap complete.

Journal:     ~/pkm/journal/YYYY-MM-DD.md (N topics)
Continuation: ~/pkm/journal/_continuations/YYYY-MM-DD.md
Updated:     <list of modified PKM notes>
Created:     <list of new PKM notes, if any>

To resume in a new session:
  cat ~/pkm/journal/_continuations/YYYY-MM-DD.md
```
