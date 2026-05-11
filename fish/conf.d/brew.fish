# Source brew shellenv on every interactive fish startup.
# Puts /opt/homebrew/bin (Apple Silicon) or /usr/local/bin (Intel) at the
# front of $PATH and sets HOMEBREW_PREFIX/CELLAR/REPOSITORY. Idempotent —
# fish_add_path with --move dedups and reorders.
#
# This is the persistence mechanism for brew PATH ordering on fish. The
# deploy script's bootstrap only adjusts the current process's PATH (so
# `brew bundle` resolves); this conf.d file handles every future shell.
if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
else if test -x /usr/local/bin/brew
    /usr/local/bin/brew shellenv fish | source
end
