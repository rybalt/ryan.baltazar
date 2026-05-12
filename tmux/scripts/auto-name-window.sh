#!/usr/bin/env bash
# Rename a freshly-created tmux window to "<cwd-basename> (N)" where N is
# the count of existing windows (across all sessions on this server) whose
# pane_current_path basename matches, plus 1.
#
# Invoked from `set-hook -g after-new-window` with the new window's ID
# passed as $1 (e.g. "@7"). With automatic-rename off, this is what gives
# new windows a useful default name instead of leaving them as "fish".

set -euo pipefail

window_id="${1:?need window id}"

path=$(tmux display-message -p -t "$window_id" '#{pane_current_path}')
base=$(basename "$path")

count=$(tmux list-windows -a -F $'#{window_id}\t#{pane_current_path}' \
        | awk -F'\t' -v target="$window_id" -v base="$base" '
            {
                n = split($2, parts, "/")
                if (parts[n] == base && $1 != target) c++
            }
            END { print c + 1 }')

tmux rename-window -t "$window_id" "$base ($count)"
