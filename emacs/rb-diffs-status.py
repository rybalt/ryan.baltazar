#!/usr/bin/env python3
"""Discover git repos and emit per-repo file status as an elisp s-expression.

Usage: rb-diffs-status.py DIR1 DIR2 ...

Each DIR is a candidate directory to check for a git repo.  The script
deduplicates by resolved toplevel, runs `git status --porcelain` in each
unique repo, and writes a single elisp-readable list to stdout.

Output format (consumed by Emacs via `(read output)`):

  (("repo-label" "/abs/toplevel"
    (:staged ("file1" "file2")
     :unstaged ("file3")
     :untracked ("file4")))
   ...)

Unity .meta files are filtered out.
"""

import os
import subprocess
import sys

os.environ["GIT_OPTIONAL_LOCKS"] = "0"
os.environ["LC_ALL"] = "C"

GIT = "git"


def git_toplevel(directory):
    """Return the git toplevel for directory, or None."""
    result = subprocess.run(
        [GIT, "-C", directory, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        return result.stdout.strip()
    return None


def git_status(toplevel):
    """Return (staged, unstaged, untracked) file lists for a repo."""
    result = subprocess.run(
        [GIT, "-C", toplevel, "status", "--porcelain"],
        capture_output=True, text=True
    )
    staged = []
    unstaged = []
    untracked = []

    for line in result.stdout.splitlines():
        if len(line) < 3:
            continue
        x, y = line[0], line[1]
        filename = line[3:]

        # Strip C-style quoting from porcelain
        if filename.startswith('"') and filename.endswith('"'):
            filename = filename[1:-1]

        # Handle renames: "old -> new"
        if " -> " in filename:
            filename = filename.split(" -> ", 1)[1]

        if x == "!" and y == "!":
            continue
        if filename.endswith(".meta"):
            continue

        if x not in (" ", "?"):
            staged.append(filename)
        if y not in (" ", "?"):
            unstaged.append(filename)
        if x == "?" and y == "?":
            untracked.append(filename)

    return staged, unstaged, untracked


def elisp_string(s):
    """Escape a string for elisp read syntax."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def elisp_string_list(items):
    """Emit a list of elisp strings."""
    if not items:
        return "()"
    return "(" + " ".join(elisp_string(f) for f in items) + ")"


def main():
    candidates = sys.argv[1:]
    if not candidates:
        sys.stdout.write("()")
        return

    # Discover unique repos
    seen = set()
    repos = []  # list of (label, toplevel)

    for candidate in candidates:
        if not os.path.isdir(candidate):
            continue
        toplevel = git_toplevel(candidate)
        if toplevel is None:
            continue
        resolved = os.path.realpath(toplevel)
        if resolved in seen:
            continue
        seen.add(resolved)
        label = os.path.basename(os.path.normpath(toplevel))
        repos.append((label, toplevel))

    # Collect status and emit
    entries = []
    for label, toplevel in repos:
        staged, unstaged, untracked = git_status(toplevel)
        entry = "({} {} (:staged {} :unstaged {} :untracked {}))".format(
            elisp_string(label),
            elisp_string(toplevel),
            elisp_string_list(staged),
            elisp_string_list(unstaged),
            elisp_string_list(untracked),
        )
        entries.append(entry)

    sys.stdout.write("(" + " ".join(entries) + ")")


if __name__ == "__main__":
    main()
