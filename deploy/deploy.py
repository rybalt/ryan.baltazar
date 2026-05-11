#!/usr/bin/env python3
"""rybalt deploy — symlink configs and run bootstrap per per-module deploy.yaml.

Discovers any top-level subdir of the repo containing a `deploy.yaml`, then for
each selected module places symlinks and runs optional bootstrap shell commands.
Idempotent and safe to re-run; conflicts on existing real files at target paths
are surfaced as a prompt (default: skip).
"""

from __future__ import annotations

import argparse
import os
import shlex
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

_PIP_HINT = (
    "python3 -m pip install --user -r deploy/requirements.txt\n"
    "  (add --break-system-packages if pip refuses with a PEP 668 message;\n"
    "   that flag is newer than system Python 3.9's pip, so don't pass it there)"
)

try:
    import yaml
except ImportError:
    sys.exit(f"Missing dep: PyYAML. Run:\n  {_PIP_HINT}")

try:
    import questionary
except ImportError:
    sys.exit(f"Missing dep: questionary. Run:\n  {_PIP_HINT}")


DEPLOY_DIR = Path(__file__).resolve().parent
REPO_ROOT = DEPLOY_DIR.parent
BREWFILE = DEPLOY_DIR / "Brewfile"
CANONICAL_HOME = Path("~/.config/rybalt").expanduser()


@dataclass
class Module:
    name: str
    path: Path
    brew_packages: list[str] = field(default_factory=list)
    pre_link: list[str] = field(default_factory=list)
    links: list[dict] = field(default_factory=list)
    post_link: list[str] = field(default_factory=list)
    next_steps: list[str] = field(default_factory=list)
    default_shell: str | None = None  # e.g. "fish"; offers `chsh` if not current


@dataclass
class LinkCounts:
    ok: int = 0
    linked: int = 0
    skipped: int = 0
    backed_up: int = 0


@dataclass
class ShellCounts:
    ok: int = 0
    failed: int = 0


@dataclass
class ModuleResult:
    links: LinkCounts = field(default_factory=LinkCounts)
    brew: ShellCounts = field(default_factory=ShellCounts)
    pre_link: ShellCounts = field(default_factory=ShellCounts)
    post_link: ShellCounts = field(default_factory=ShellCounts)


@dataclass
class RunResult:
    bootstrap_path: str | None = None
    bootstrap_brewfile: str | None = None
    bootstrap_home: str | None = None
    modules: dict[str, ModuleResult] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)
    next_steps: dict[str, list[str]] = field(default_factory=dict)


# ---------- discovery & CLI ----------

def discover_modules() -> list[Module]:
    found: list[Module] = []
    for sub in sorted(REPO_ROOT.iterdir()):
        if not sub.is_dir() or sub.name.startswith("."):
            continue
        manifest = sub / "deploy.yaml"
        if not manifest.is_file():
            continue
        data = yaml.safe_load(manifest.read_text())
        if data is None:
            data = {}
        elif not isinstance(data, dict):
            sys.exit(f"Malformed manifest at {manifest}: expected a YAML "
                     f"mapping at the top level, got {type(data).__name__}.")
        found.append(
            Module(
                name=sub.name,
                path=sub,
                brew_packages=data.get("brew_packages") or [],
                pre_link=data.get("pre_link") or [],
                links=data.get("links") or [],
                post_link=data.get("post_link") or [],
                next_steps=data.get("next_steps") or [],
                default_shell=data.get("default_shell"),
            )
        )
    return found


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="deploy",
        description="rybalt deploy: symlinks + bootstrap per per-module deploy.yaml.",
    )
    p.add_argument("--all", action="store_true",
                   help="Deploy every discovered module (no TUI).")
    p.add_argument(
        "--modules",
        type=lambda s: [m.strip() for m in s.split(",") if m.strip()],
        help="Comma-separated module names to deploy (no TUI).",
    )
    p.add_argument("--dry-run", action="store_true",
                   help="Print every action; perform none.")
    p.add_argument("--yes", action="store_true",
                   help="Auto-skip conflicts (non-interactive).")
    p.add_argument("--skip-brew", action="store_true",
                   help="Skip Brewfile and per-module brew_packages.")
    p.add_argument("--skip-shell", action="store_true",
                   help="Skip pre_link and post_link phases.")
    return p.parse_args(argv)


def select_modules(modules: list[Module], args: argparse.Namespace) -> list[Module]:
    if args.all:
        return modules
    if args.modules is not None:
        if not args.modules:
            sys.exit("--modules requires at least one module name.")
        by_name = {m.name: m for m in modules}
        missing = [n for n in args.modules if n not in by_name]
        if missing:
            sys.exit(f"Unknown module(s): {', '.join(missing)}. "
                     f"Available: {', '.join(by_name)}")
        return [by_name[n] for n in args.modules]
    if not sys.stdin.isatty():
        sys.exit("No --all or --modules and stdin isn't a TTY — refusing to guess.")
    chosen = questionary.checkbox(
        "Select modules to deploy",
        choices=[questionary.Choice(m.name, checked=True) for m in modules],
    ).ask()
    if chosen is None:
        sys.exit("Cancelled.")
    by_name = {m.name: m for m in modules}
    return [by_name[n] for n in chosen]


# ---------- bootstrap ----------

def bootstrap_path(args: argparse.Namespace, result: RunResult, has_brew: bool):
    """Prepend brew's bin/sbin to the *current process* PATH so subsequent
    subprocesses (especially `brew bundle`) resolve cleanly. Long-term
    persistence for fish sessions is handled by `fish/conf.d/brew.fish`
    in the fish module — that file sources `brew shellenv` at every fish
    startup, which is more reliable than universal vars (which can get
    backed-up-away during the fish module's own symlink swap).

    zsh/bash users should add `eval "$(brew shellenv)"` to their rc themselves.
    """
    if not has_brew:
        result.bootstrap_path = "skipped (no brew)"
        print("[bootstrap] PATH: skipped (brew not on PATH)")
        return
    brew = shutil.which("brew") or "brew"

    prefix = subprocess.run(
        [brew, "--prefix"], capture_output=True, text=True, check=False
    ).stdout.strip()
    if not prefix:
        result.bootstrap_path = "skipped (brew --prefix returned empty)"
        return
    bin_dir = f"{prefix}/bin"
    sbin_dir = f"{prefix}/sbin"

    parts = os.environ.get("PATH", "").split(os.pathsep)
    if bin_dir in parts[:2]:
        result.bootstrap_path = "ok (already at front of $PATH)"
        print(f"[bootstrap] PATH: {bin_dir} already at front")
        return
    if args.dry_run:
        print(f"[dry-run] prepend {bin_dir} and {sbin_dir} to current PATH")
        result.bootstrap_path = "would prepend (dry-run)"
        return
    os.environ["PATH"] = os.pathsep.join([bin_dir, sbin_dir] + parts)
    result.bootstrap_path = "ok (prepended for current process)"
    print(f"[bootstrap] PATH: {bin_dir} prepended (current process; "
          "fish persistence handled by fish/conf.d/brew.fish)")


def bootstrap_brewfile(args: argparse.Namespace, result: RunResult, has_brew: bool):
    if args.skip_brew:
        result.bootstrap_brewfile = "skipped (--skip-brew)"
        print("[bootstrap] Brewfile: skipped (--skip-brew)")
        return
    if not BREWFILE.is_file():
        result.bootstrap_brewfile = "no Brewfile"
        return
    if not has_brew:
        result.bootstrap_brewfile = "skipped (brew not on PATH)"
        result.warnings.append("brew not on PATH — Brewfile skipped")
        print("[bootstrap] Brewfile: skipped (brew not on PATH)")
        return
    if args.dry_run:
        print(f"[dry-run] brew bundle --file {BREWFILE}")
        result.bootstrap_brewfile = "dry-run"
        return
    print(f"[bootstrap] brew bundle --file {BREWFILE}")
    proc = subprocess.run(["brew", "bundle", "--file", str(BREWFILE)], check=False)
    if proc.returncode == 0:
        result.bootstrap_brewfile = "ok"
    else:
        result.bootstrap_brewfile = f"failed (exit {proc.returncode})"
        result.warnings.append(f"brew bundle exited {proc.returncode}")


def bootstrap_home(args: argparse.Namespace, result: RunResult):
    desired = REPO_ROOT.resolve()
    target = CANONICAL_HOME
    if target.is_symlink():
        try:
            if target.resolve() == desired:
                result.bootstrap_home = "ok (already a symlink to repo)"
                print(f"[bootstrap] {target} -> ok")
                return
        except OSError:
            pass
    if not target.exists() and not target.is_symlink():
        if args.dry_run:
            print(f"[dry-run] symlink {target} -> {desired}")
            result.bootstrap_home = "would link (dry-run)"
            return
        target.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(desired, target)
        result.bootstrap_home = "linked"
        print(f"[bootstrap] {target} -> linked")
        return
    # Conflict path. In dry-run, skip the prompt; describe what we'd ask.
    if args.dry_run:
        descr = describe_target(target)
        print(f"[dry-run] {target} exists as {descr}; would prompt (default skip)")
        result.bootstrap_home = "would prompt (dry-run)"
        return
    choice = prompt_conflict(target, args)
    if choice == "skip":
        result.bootstrap_home = "skipped (conflict)"
        result.warnings.append(
            f"{target} not pointing at repo — downstream configs that look up "
            f"files via this canonical path may fail to find them"
        )
    elif choice == "backup":
        backup_path = backup_aside(target)
        os.symlink(desired, target)
        result.bootstrap_home = f"backed up to {backup_path.name}; linked"
        print(f"[bootstrap] {target} -> linked "
              f"(existing moved to {backup_path.name})")
    elif choice == "abort":
        sys.exit(f"Aborted at bootstrap: {target} conflict.")


# ---------- per-module ----------

def deploy_module(m: Module, args: argparse.Namespace,
                  result: RunResult, has_brew: bool):
    mr = ModuleResult()
    result.modules[m.name] = mr

    # 1. brew_packages
    if m.brew_packages:
        if args.skip_brew:
            print(f"[{m.name}] brew_packages: skipped (--skip-brew)")
        elif not has_brew:
            result.warnings.append(
                f"{m.name}: brew missing, skipped {len(m.brew_packages)} packages"
            )
        else:
            for pkg in m.brew_packages:
                cmd = ["brew", "install", *shlex.split(pkg)]
                if args.dry_run:
                    print(f"[dry-run] [{m.name}] {' '.join(cmd)}")
                    mr.brew.ok += 1
                    continue
                print(f"[{m.name}] {' '.join(cmd)}")
                proc = subprocess.run(cmd, check=False)
                if proc.returncode == 0:
                    mr.brew.ok += 1
                else:
                    mr.brew.failed += 1
                    result.warnings.append(
                        f"{m.name}: brew install {pkg} failed"
                    )

    # 2. pre_link
    run_shell_phase(m, m.pre_link, "pre_link", args, result, mr.pre_link)

    # 3. links
    for entry in m.links:
        src = (m.path / entry["source"]).resolve()
        tgt = Path(entry["target"]).expanduser()
        place_link(src, tgt, args, mr.links, result, label=m.name)

    # 4. post_link
    run_shell_phase(m, m.post_link, "post_link", args, result, mr.post_link)

    # 5. default_shell (optional chsh, prompted)
    if m.default_shell:
        maybe_set_default_shell(m, args, result)

    # 6. next_steps (collected for end-of-run printing)
    if m.next_steps:
        result.next_steps[m.name] = list(m.next_steps)


def run_shell_phase(m: Module, cmds: list[str], phase_name: str,
                    args: argparse.Namespace, result: RunResult,
                    counts: ShellCounts):
    if not cmds:
        return
    if args.skip_shell:
        print(f"[{m.name}] {phase_name}: skipped (--skip-shell)")
        return
    for cmd in cmds:
        if args.dry_run:
            print(f"[dry-run] [{m.name}] {phase_name}: {cmd}")
            counts.ok += 1
            continue
        print(f"[{m.name}] {phase_name}: {cmd}")
        proc = subprocess.run(cmd, shell=True, check=False)
        if proc.returncode == 0:
            counts.ok += 1
        else:
            counts.failed += 1
            result.warnings.append(
                f"{m.name}: {phase_name} failed (exit {proc.returncode}): {cmd}"
            )


def place_link(src: Path, tgt: Path, args: argparse.Namespace,
               counts: LinkCounts, result: RunResult, label: str):
    if not src.exists():
        counts.skipped += 1
        result.warnings.append(
            f"{label}: source {src} does not exist; link skipped"
        )
        print(f"[{label}] link {tgt} -> skipped (source missing: {src})")
        return
    if tgt.is_symlink():
        try:
            if tgt.resolve() == src.resolve():
                counts.ok += 1
                print(f"[{label}] link {tgt} -> ok")
                return
        except OSError:
            pass
    if not tgt.exists() and not tgt.is_symlink():
        if args.dry_run:
            print(f"[dry-run] [{label}] symlink {tgt} -> {src}")
            counts.linked += 1
            return
        tgt.parent.mkdir(parents=True, exist_ok=True)
        os.symlink(src, tgt)
        counts.linked += 1
        print(f"[{label}] {tgt} -> linked")
        return
    # Conflict path. In dry-run, don't fire the interactive prompt — just
    # describe what we'd ask and count it as a skip (the default).
    if args.dry_run:
        descr = describe_target(tgt)
        print(f"[dry-run] [{label}] {tgt} exists as {descr}; "
              f"would prompt (default skip)")
        counts.skipped += 1
        return
    choice = prompt_conflict(tgt, args)
    if choice == "skip":
        counts.skipped += 1
        result.warnings.append(f"{label}: {tgt} existed, skipped")
        return
    if choice == "backup":
        backup_path = backup_aside(tgt)
        os.symlink(src, tgt)
        counts.backed_up += 1
        print(f"[{label}] {tgt} -> linked (existing moved to {backup_path.name})")
        return
    if choice == "abort":
        sys.exit(f"Aborted at {label}: {tgt} conflict.")


def maybe_set_default_shell(m: Module, args: argparse.Namespace,
                            result: RunResult):
    """If the module declares `default_shell: <name>`, and that shell isn't
    already the user's login shell, prompt to chsh into it. Adds the shell
    to /etc/shells first (via `sudo tee -a`) when necessary.
    Honors --dry-run (describe) and --yes (auto-decline)."""
    shell_name = m.default_shell
    if not shell_name:
        return
    shell_path = shutil.which(shell_name)
    if not shell_path:
        result.warnings.append(
            f"{m.name}: cannot find {shell_name} on PATH; "
            "skipping default-shell setup"
        )
        return
    current = os.environ.get("SHELL", "")
    try:
        if current and Path(current).resolve() == Path(shell_path).resolve():
            return  # already default
    except OSError:
        pass  # current shell path resolution failed; proceed to prompt
    if args.dry_run:
        print(f"[dry-run] [{m.name}] would prompt to chsh to {shell_path} "
              f"(current: {current or 'unset'})")
        return
    if args.yes:
        return  # non-interactive: default is "no, don't change"
    print(f"[{m.name}] current login shell: {current or '(unset)'}")
    confirmed = questionary.confirm(
        f"Set {shell_path} as your default login shell?",
        default=False,
    ).ask()
    if not confirmed:
        return
    # /etc/shells must list the shell for chsh to accept it.
    try:
        shells_lines = Path("/etc/shells").read_text().splitlines()
    except OSError as exc:
        result.warnings.append(f"{m.name}: cannot read /etc/shells: {exc}")
        return
    if shell_path not in shells_lines:
        print(f"[{m.name}] {shell_path} not in /etc/shells; "
              "adding (sudo will prompt)")
        proc = subprocess.run(
            ["sudo", "tee", "-a", "/etc/shells"],
            input=f"{shell_path}\n",
            text=True,
            check=False,
            stdout=subprocess.DEVNULL,  # tee echoes input; suppress
        )
        if proc.returncode != 0:
            result.warnings.append(
                f"{m.name}: failed to add {shell_path} to /etc/shells"
            )
            return
    print(f"[{m.name}] chsh -s {shell_path}")
    proc = subprocess.run(["chsh", "-s", shell_path], check=False)
    if proc.returncode == 0:
        print(f"[{m.name}] default shell changed "
              "(effective on next login)")
    else:
        result.warnings.append(
            f"{m.name}: chsh exited {proc.returncode}"
        )


def prompt_conflict(tgt: Path, args: argparse.Namespace) -> str:
    if args.yes:
        return "skip"
    descr = describe_target(tgt)
    print(f"[conflict] {tgt} exists as {descr}.")
    choice = questionary.select(
        "What now?",
        choices=[
            questionary.Choice("skip (leave as-is)", value="skip"),
            questionary.Choice(
                f"backup ({tgt.name}.bak.<timestamp>) and link",
                value="backup",
            ),
            questionary.Choice("abort entire run", value="abort"),
        ],
        default="skip",  # match a choice's value, not its title
    ).ask()
    return choice or "abort"


def describe_target(tgt: Path) -> str:
    if tgt.is_symlink():
        try:
            return f"a symlink pointing at {os.readlink(tgt)}"
        except OSError:
            return "a (broken) symlink"
    if tgt.is_dir():
        return "a regular directory"
    if tgt.is_file():
        return "a regular file"
    return "something unexpected"


def backup_aside(tgt: Path) -> Path:
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_path = tgt.with_name(f"{tgt.name}.bak.{ts}")
    tgt.rename(backup_path)
    return backup_path


# ---------- summary ----------

def print_summary(result: RunResult):
    print()
    print("== rybalt deploy summary ==")
    print("bootstrap:")
    print(f"  PATH (current proc)  -> {result.bootstrap_path or 'not run'}")
    print(f"  Brewfile             -> {result.bootstrap_brewfile or 'not run'}")
    print(f"  ~/.config/rybalt     -> {result.bootstrap_home or 'not run'}")
    print("modules:")
    for name, mr in result.modules.items():
        parts: list[str] = []
        L = mr.links
        bits = []
        if L.ok:
            bits.append(f"{L.ok} ok")
        if L.linked:
            bits.append(f"{L.linked} linked")
        if L.skipped:
            bits.append(f"{L.skipped} skipped")
        if L.backed_up:
            bits.append(f"{L.backed_up} backed-up")
        if bits:
            parts.append("links: " + ", ".join(bits))
        for phase_name, sc in (("brew", mr.brew),
                                ("pre_link", mr.pre_link),
                                ("post_link", mr.post_link)):
            if sc.ok or sc.failed:
                s = f"{phase_name}: {sc.ok} ok"
                if sc.failed:
                    s += f", {sc.failed} failed"
                parts.append(s)
        print(f"  {name:20s} {'; '.join(parts) if parts else '(nothing to do)'}")
    if result.warnings:
        print(f"warnings: {len(result.warnings)}")
        for w in result.warnings:
            print(f"  - {w}")
    if result.next_steps:
        print("next steps:")
        for mod_name, steps in result.next_steps.items():
            for s in steps:
                print(f"  {mod_name}: {s}")


# ---------- entry ----------

def main():
    args = parse_args()
    modules = discover_modules()
    if not modules:
        sys.exit(f"No modules found under {REPO_ROOT}.")
    selected = select_modules(modules, args)
    has_brew = bool(shutil.which("brew"))
    result = RunResult()
    bootstrap_path(args, result, has_brew)
    bootstrap_brewfile(args, result, has_brew)
    bootstrap_home(args, result)
    for m in selected:
        print(f"\n-- {m.name} --")
        deploy_module(m, args, result, has_brew)
    print_summary(result)


if __name__ == "__main__":
    main()
