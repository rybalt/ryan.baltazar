# rb-prompt: prompt data-collection and configuration layer.
#
# Computes:
#   * The formatted PWD whenever PWD or fish_prompt_pwd_dir_length changes.
#   * The git block (branch + dirty + ahead/behind) asynchronously on every
#     prompt event, written to the per-pid universal var named in
#     $_rb_prompt_git_var. A variable-watcher on that name triggers prompt
#     repaint when the async subshell finishes.
#
# Future diffs add HEAD/index caching, throttled fetch, worktree/in-progress
# detection, and host context.
#
# The renderer lives in functions/fish_prompt.fish and reads $_rb_prompt_pwd
# and $$_rb_prompt_git_var (the double-deref reads the per-pid var by name).
#
# The truncation regex, git-base preservation pattern, and async-subshell
# pattern below are adapted from Hydro (https://github.com/jorgebucaran/hydro),
# MIT License, (c) Jorge Bucaran. The same regex shape is also used by fish's
# stock prompt_pwd; we extend it with git-base preservation, last-segment
# bolding, dimmed slashes, and our own async git data collection (no
# untracked-file enumeration, fish_pid-scoped vars).

status is-interactive || exit

# Per-pid universal-var name used to pass the formatted git string from the
# async subshell back to the prompt renderer.
set --global _rb_prompt_git_var _rb_prompt_git_$fish_pid

# Watcher: when the per-pid var changes, the prompt repaints.
function $_rb_prompt_git_var --on-variable $_rb_prompt_git_var
    commandline --function repaint
end

# PWD formatter: leading-dot-aware parent shrinking, git-base preserved,
# cwd basename bolded, slashes dimmed.
function _rb_prompt_pwd --on-variable PWD --on-variable fish_prompt_pwd_dir_length
    set -l git_root (command git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
    set -l git_base (string replace --all --regex -- "^.*/" "" "$git_root")
    set -l path_sep /

    test "$fish_prompt_pwd_dir_length" = 0; and set path_sep

    set --global _rb_prompt_pwd (
        string replace --ignore-case -- ~ \~ $PWD |
        string replace -- "/$git_base/" /:/ |
        string replace --regex --all -- "(\.?[^/]{"(
            string replace --regex --all -- '^$' 1 "$fish_prompt_pwd_dir_length"
        )"})[^/]*/" "\$1$path_sep" |
        string replace -- : "$git_base" |
        string replace --regex -- '([^/]+)$' "\x1b[1m\$1\x1b[22m" |
        string replace --regex --all -- '(?!^/$)/|^$' "\x1b[2m/\x1b[22m"
    )
end

# Async git data collection. Runs on every fish_prompt event; spawns a
# backgrounded subshell that does a few cheap git invocations and writes
# the formatted result back via the per-pid universal var.
function _rb_prompt_run --on-event fish_prompt
    # Cancel any subshell still in flight from the previous prompt.
    command kill $_rb_prompt_last_pid 2>/dev/null

    set -l git_root (command git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)

    # Not in a git repo, or path is on the opt-out list — clear the var.
    if not set --query git_root[1]; or contains -- $git_root $rb_prompt_ignored_paths
        set --universal $_rb_prompt_git_var ''
        return
    end

    fish --private --command "
        set branch (
            command git branch --show-current 2>/dev/null ||
            command git describe --tags --exact-match HEAD 2>/dev/null ||
            command git rev-parse --short HEAD 2>/dev/null |
                string replace --regex -- '(.+)' '@\$1'
        )

        # Show the branch name immediately if the var is empty (first
        # render in this directory). The rest of the subshell adds dirty
        # and upstream info, then updates with the full string.
        test -z \"\$$_rb_prompt_git_var\" && set --universal $_rb_prompt_git_var \"\$branch \"

        # Dirty check — tracked files only. No untracked enumeration
        # (which is the slow path on monorepos).
        set info ''
        command git diff-index --quiet HEAD 2>/dev/null
        test \$status -eq 1 && set info '$rb_prompt_git_dirty'

        # Ahead / behind vs upstream. Empty if no upstream is configured.
        command git rev-list --count --left-right @{upstream}...@ 2>/dev/null |
            read behind ahead

        set upstream ''
        switch \"\$behind \$ahead\"
            case ' ' '0 0'
                # No upstream, or in sync — leave upstream empty.
            case '0 *'
                set upstream \" $rb_prompt_git_ahead\$ahead\"
            case '* 0'
                set upstream \" $rb_prompt_git_behind\$behind\"
            case '*'
                set upstream \" $rb_prompt_git_ahead\$ahead $rb_prompt_git_behind\$behind\"
        end

        set --universal $_rb_prompt_git_var \"\$branch\$info\$upstream \"
    " &

    set --global _rb_prompt_last_pid $last_pid
end

# Erase the per-pid var when the shell exits, so universal storage doesn't
# accumulate vars from dead shells.
function _rb_prompt_fish_exit --on-event fish_exit
    set --erase $_rb_prompt_git_var
end

# Symbol defaults — overridable via universal vars.
set --query rb_prompt_git_dirty;  or set --global rb_prompt_git_dirty •
set --query rb_prompt_git_ahead;  or set --global rb_prompt_git_ahead ↑
set --query rb_prompt_git_behind; or set --global rb_prompt_git_behind ↓
