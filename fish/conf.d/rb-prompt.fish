# rb-prompt: prompt data-collection and configuration layer.
#
# This file is the home for the prompt's async git data collection,
# HEAD/index caching, throttled fetch, worktree/in-progress detection,
# and host context. Future diffs (5+) flesh it out.
#
# The renderer lives in functions/fish_prompt.fish and reads computed
# values from this file via universal variables. There is no Hydro
# dependency — see PLAN.md "Architecture" for rationale.

status is-interactive || exit
