function fish_prompt --description 'Two-line prompt: status line + symbol line'
    set -l last_status $status
    set -l normal (set_color normal)

    # Since the prompt symbol is on its own line, allow longer dir names.
    set -q fish_prompt_pwd_dir_length
        or set -lx fish_prompt_pwd_dir_length 0

    set -l cwd_color (set_color $fish_color_cwd)
    set -l vcs_color (set_color brpurple)
    set -l err_color (set_color $fish_color_error)
    set -l ok_color  (set_color brgreen)

    set -l suffix '❯'
    if functions -q fish_is_root_user; and fish_is_root_user
        set -q fish_color_cwd_root; and set cwd_color (set_color $fish_color_cwd_root)
        set suffix '#'
    end

    # Compute PWD on first render if the PWD-change watcher hasn't fired.
    set --query _rb_prompt_pwd; or _rb_prompt_pwd

    # Line 1 components.
    set -l host_marker (_rb_prompt_host)
    set -l pwd_str $_rb_prompt_pwd
    set -l git_str $$_rb_prompt_git_var

    # Budget for line 1: defaults to the terminal width ($COLUMNS, auto-updated
    # by fish on SIGWINCH), with a floor of 80 chars so we don't over-compress
    # in narrow split panes. Explicit $rb_prompt_max_width overrides everything.
    # Compression order: shrink git-base in PWD -> middle-ellipsize branch ->
    # accept overflow.
    set -l max_width 120
    set -q COLUMNS; and test $COLUMNS -gt 0; and set max_width $COLUMNS
    test $max_width -lt 80; and set max_width 80
    set -q rb_prompt_max_width; and set max_width $rb_prompt_max_width

    set -l visible (string length --visible "$host_marker$pwd_str $git_str")

    if test $visible -gt $max_width
        set pwd_str (_rb_prompt_compress_pwd_base $pwd_str)
        set visible (string length --visible "$host_marker$pwd_str $git_str")
    end

    if test $visible -gt $max_width
        set git_str (_rb_prompt_compress_branch $git_str)
    end

    echo -s $host_marker $cwd_color $pwd_str $normal ' ' $vcs_color $git_str $normal

    # Line 2: [error-code] symbol
    if test $last_status -ne 0
        echo -n -s $err_color "[$last_status] " $suffix ' ' $normal
    else
        echo -n -s $ok_color $suffix ' ' $normal
    end
end
