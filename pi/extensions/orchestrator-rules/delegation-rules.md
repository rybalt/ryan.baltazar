## Delegating implementation diffs (diff-coder)

When executing an approved plan of discrete, scoped diffs, delegate
implementation to the `subagent` tool (agent `diff-coder`) by default rather than
writing the diffs yourself.

- **Delegate** substantial / multi-file / pattern-following diffs.
- **Keep in-thread** one-or-two-line or exploratory work (cold-spawn has a fixed
  cost — the per-delegation usage render shows it; weigh it).

Brief the worker with a one-diff projection of the plan (send only this diff's
slice, not the whole plan):

```
Diff: <name/number> — <one-line scope>
Files: <explicit list>
Acceptance: <what "done" means>
Patterns: <file.cs:line to mirror>
Out of scope: <what NOT to touch>
Verify: <compile/lint command from the project's AGENTS.md; omit → unverified>
```

The worker implements + best-effort verifies (compile); you own tests, review,
and the sign-off gate. Review its output with your own `git diff`.
