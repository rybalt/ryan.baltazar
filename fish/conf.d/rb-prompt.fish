# rb-prompt: prompt data-collection and configuration layer.
#
# Computes the formatted PWD whenever PWD or fish_prompt_pwd_dir_length
# changes. Future diffs add async git data collection, HEAD/index caching,
# throttled fetch, worktree/in-progress detection, and host context.
#
# The renderer lives in functions/fish_prompt.fish and reads computed
# values from this file via global variables.
#
# The truncation regex and git-base preservation pattern below are
# adapted from Hydro (https://github.com/jorgebucaran/hydro), MIT License,
# (c) Jorge Bucaran. The same regex shape is also used by fish's stock
# prompt_pwd; we extend it with git-base preservation, last-segment
# bolding, and dimmed slashes.

status is-interactive || exit

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
