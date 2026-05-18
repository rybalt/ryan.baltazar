function attach-claude-primary --description 'Attach to (or create) the persistent claude-primary tmux session'
    # Attach if the session exists; if `tmux attach -t` exits non-zero
    # (the usual case when the session is missing), create it with `claude`
    # as PID 1 so closing claude tears the session down. Next invocation
    # then re-creates it fresh.
    tmux attach -t claude-primary
        or tmux new-session -s claude-primary claude
end
