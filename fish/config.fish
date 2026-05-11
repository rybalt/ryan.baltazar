if status is-interactive
    # Vi-style keybindings. The mode letter (N/I/R/V) shows in the right
    # prompt via fish_right_prompt; fish_mode_prompt is a no-op (we
    # deliberately don't render the mode on the left prompt line).
    fish_vi_key_bindings

    # Truncate parent directories to a single char (with leading dot
    # preserved) in the prompt PWD. The cwd basename and the git-base
    # directory are preserved full by _rb_prompt_pwd in conf.d/rb-prompt.fish.
    set -g fish_prompt_pwd_dir_length 1

    # Machine-specific Unity work setup, only present on that box.
    test -f /opt/UnitySrc/repos/rybalt-unity/rb-setup.fish
        and source /opt/UnitySrc/repos/rybalt-unity/rb-setup.fish
end
