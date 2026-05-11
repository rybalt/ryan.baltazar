# Fish color theme — applied each shell startup.
#
# Equivalent to fish's built-in `default` theme (verbatim from
# /opt/homebrew/share/fish/themes/default.theme), baked into the repo as
# `set -g` calls instead of being saved to fish_variables.
#
# Why repo-controlled: fish_variables is gitignored (machine-local
# interactive state) so themes saved via `fish_config theme save` don't
# travel across machines. This conf.d file is on the symlink path, so it
# does.
#
# Why the `default` theme specifically: uses ANSI named colors
# (brblack, cyan, red, …) which the *terminal* theme maps to specific
# RGB. So `GitHub Light High Contrast` and `GitHub Dark High Contrast`
# both render this fish theme readably as you auto-switch by system
# appearance.

# --- foreground colors ---
set -g fish_color_normal --reset
set -g fish_color_autosuggestion brblack
set -g fish_color_command --reset
set -g fish_color_comment red
set -g fish_color_cwd green
set -g fish_color_cwd_root red
set -g fish_color_end green
set -g fish_color_error brred
set -g fish_color_escape brcyan
set -g fish_color_host --reset
set -g fish_color_host_remote yellow
set -g fish_color_operator brcyan
set -g fish_color_param cyan
set -g fish_color_quote yellow
set -g fish_color_redirection cyan --bold
set -g fish_color_status red
set -g fish_color_user brgreen
set -g fish_color_valid_path --underline

# --- editor state ---
set -g fish_color_cancel -r
set -g fish_color_history_current --bold
# Selection/match: IDE-style bright-white-on-blue.
#
# Note: on GitHub Light High Contrast, ANSI brwhite maps to a slightly
# gray-ish off-white rather than pure white, so the selection reads softer
# than a true IDE highlight. Accepted as-is — the alternative options
# (dark-on-light-blue, RGB pinning) trade off aesthetics that the user
# prefers to keep.
set -g fish_color_search_match brwhite --background=blue --bold
set -g fish_color_selection brwhite --background=blue --bold

# --- pager (tab completions) ---
set -g fish_pager_color_description yellow --italics
set -g fish_pager_color_prefix --bold --underline
set -g fish_pager_color_progress brwhite --background=cyan --bold
set -g fish_pager_color_selected_background -r
