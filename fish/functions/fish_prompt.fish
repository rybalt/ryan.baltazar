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

    # Line 1: [host?] cwd git
    # _rb_prompt_host emits "[host][nix:name][container] " when applicable,
    # empty otherwise. The git block ($$_rb_prompt_git_var) is set
    # asynchronously by _rb_prompt_run in conf.d/rb-prompt.fish.
    echo -s (_rb_prompt_host) $cwd_color $_rb_prompt_pwd $normal ' ' $vcs_color $$_rb_prompt_git_var $normal

    # Line 2: [error-code] symbol
    if test $last_status -ne 0
        echo -n -s $err_color "[$last_status] " $suffix ' ' $normal
    else
        echo -n -s $ok_color $suffix ' ' $normal
    end
end
