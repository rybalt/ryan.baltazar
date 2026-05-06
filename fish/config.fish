if status is-interactive
    # Truncate parent directories to a single char (with leading dot
    # preserved) in the prompt PWD. The cwd basename and the git-base
    # directory are preserved full by _rb_prompt_pwd in conf.d/rb-prompt.fish.
    set -g fish_prompt_pwd_dir_length 1

    # Commands to run in interactive sessions can go here
    source /opt/UnitySrc/repos/rybalt-unity/rb-setup.fish
end
