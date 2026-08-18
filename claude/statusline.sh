#!/usr/bin/env bash
# Claude Code status line — fish-prompt-flavored.
#
# Renders one line:
#   <cwd>  <git>   │   <model>  ctx <used> (<pct%>)  $cost
#
# Design ported from the rybalt fish prompt (fish/functions/fish_prompt.fish,
# fish/conf.d/rb-prompt.fish):
#   * cwd: parent dirs shrink to leading-dot + 1 char, git-base kept full,
#     basename bold, slashes dimmed.
#   * git: branch + '•' dirty + '↑n ↓m' upstream + '[wt:name]' worktree +
#     in-progress state (⏸ rebase / ⇄ merge / ⇒ cherry-pick / ⇆ bisect).
#   * ANSI *named* colors only (no RGB), matching fish/conf.d/colors.fish, so
#     the line stays readable under both light and dark terminal themes.
#
# Claude-Code-specific segments (no fish analog): model name, context used
# (parsed from the transcript), and cost (from the JSON).
#
# Input: session JSON on stdin. Output: first line -> the status line.
# Config (all env vars, all fall back safely on bad values):
#   CLAUDE_STATUSLINE_CTX_GREEN   green ceiling in tokens (default 200000)
#   CLAUDE_STATUSLINE_CTX_YELLOW  yellow ceiling in tokens (default 400000);
#                                 also the 100% mark of the wrap-up budget %

set -o pipefail

# --- ANSI (named / standard SGR only) -----------------------------------------
RST=$'\033[0m'
DIM=$'\033[2m'
UNDIM=$'\033[22m'
BLD=$'\033[1m'
UNBLD=$'\033[22m'
GREEN=$'\033[32m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
MAGENTA=$'\033[95m' # brpurple in fish
sep="${DIM}/${UNDIM}"

# --- read stdin JSON ----------------------------------------------------------
json=$(cat)
q() { printf '%s' "$json" | jq -r "$1" 2>/dev/null; }

# Human-readable token count: 950 -> "950", 49937 -> "50k", 1234000 -> "1.2M".
fmt_tokens() {
  local t=$1
  if ((t >= 1000000)); then
    printf '%d.%dM' $((t / 1000000)) $(((t % 1000000) / 100000))
  elif ((t >= 1000)); then
    printf '%dk' $(((t + 500) / 1000))
  else printf '%d' "$t"; fi
}

cwd=$(q '.workspace.current_dir // .cwd // empty')
[[ -z $cwd ]] && cwd=$PWD
model_name=$(q '.model.display_name // empty')
transcript=$(q '.transcript_path // empty')
cost=$(q '.cost.total_cost_usd // 0')

git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
git_base=""
[[ -n $git_root ]] && git_base=$(basename "$git_root")

disp=$cwd
if [[ $cwd == "$HOME" ]]; then
  disp="~"
elif [[ $cwd == "$HOME"/* ]]; then
  disp="~/${cwd#"$HOME"/}"
fi

lead=""
[[ $disp == /* ]] && lead="$sep"
disp="${disp#/}"
IFS='/' read -ra segs <<<"$disp"
n=${#segs[@]}
cwd_body=""
for ((i = 0; i < n; i++)); do
  s="${segs[i]}"
  if ((i == n - 1)); then
    rendered="${BLD}${s}${UNBLD}" # basename: full + bold
  elif [[ "$s" == "$git_base" && -n "$git_base" ]] || [[ "$s" == "~" ]]; then
    rendered="$s" # git-base / home: full
  elif [[ "$s" == .* ]]; then
    rendered=".${s:1:1}" # leading dot + 1 char
  else
    rendered="${s:0:1}" # first char
  fi
  if ((i == 0)); then cwd_body="$rendered"; else cwd_body="${cwd_body}${sep}${rendered}"; fi
done
cwd_seg="${GREEN}${lead}${cwd_body}${RST}"

# --- git block ----------------------------------------------------------------
git_seg=""
gd=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null)
if [[ -n $gd ]]; then
  # worktree marker: parent repo basename (worktree's own name is the cwd base)
  worktree=""
  if [[ $gd == */worktrees/* ]]; then
    common=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
    [[ -n $common ]] && worktree=" [wt:$(basename "$(dirname "$common")")]"
  fi

  # in-progress state + recovered branch
  state=""
  state_branch=""
  if [[ -d $gd/rebase-merge ]]; then
    state_branch=$(sed 's#^refs/heads/##' "$gd/rebase-merge/head-name" 2>/dev/null)
    state=" ⏸ rebase $(cat "$gd/rebase-merge/msgnum" 2>/dev/null)/$(cat "$gd/rebase-merge/end" 2>/dev/null)"
  elif [[ -d $gd/rebase-apply ]]; then
    state_branch=$(sed 's#^refs/heads/##' "$gd/rebase-apply/head-name" 2>/dev/null)
    state=" ⏸ rebase"
  elif [[ -e $gd/MERGE_HEAD ]]; then
    state=" ⇄ merge"
  elif [[ -e $gd/CHERRY_PICK_HEAD ]]; then
    state=" ⇒ cherry-pick"
  elif [[ -e $gd/BISECT_LOG ]]; then
    state=" ⇆ bisect"
  fi

  if [[ -n $state_branch ]]; then
    branch=$state_branch
  else
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [[ -z $branch ]] && branch=$(git -C "$cwd" describe --tags --exact-match HEAD 2>/dev/null)
    [[ -z $branch ]] && {
      short=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
      [[ -n $short ]] && branch="@$short"
    }
  fi

  dirty=""
  git -C "$cwd" diff-index --quiet HEAD -- 2>/dev/null || dirty="•"

  upstream=""
  if read -r behind ahead < <(git -C "$cwd" rev-list --count --left-right '@{upstream}...@' 2>/dev/null); then
    ((ahead > 0)) && upstream+=" ↑$ahead"
    ((behind > 0)) && upstream+=" ↓$behind"
  fi

  [[ -n $branch ]] && git_seg="  ${MAGENTA}${branch}${worktree}${state}${dirty}${upstream}${RST}"
fi

# --- model --------------------------------------------------------------------
model_seg=""
[[ -n $model_name ]] && model_seg="${CYAN}${model_name}${RST}"

# --- context used (from transcript) -------------------------------------------
ctx_seg=""
if [[ -n $transcript && -f $transcript ]]; then
  used=$(jq -rc 'select(.isSidechain != true and (.message.usage != null))
        | (.message.usage
           | .input_tokens + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))' \
    "$transcript" 2>/dev/null | tail -1)
  if [[ $used =~ ^[0-9]+$ ]]; then
    # Color by *absolute* tokens, not fraction of the window: degradation
    # tracks token count, not window fraction (650k on a 1M window is far
    # worse than the same 65% on a 200k window). Bands tuned for practical
    # Opus coding work — ~2x the adversarial breakpoints, since Opus decays
    # slowest of the vendors: green <200k, yellow 200-400k, red >400k. Each
    # threshold is env-overridable; bad values fall back to the default.
    green_max=${CLAUDE_STATUSLINE_CTX_GREEN:-200000}
    yellow_max=${CLAUDE_STATUSLINE_CTX_YELLOW:-400000}
    [[ $green_max =~ ^[1-9][0-9]*$ ]] || green_max=200000
    [[ $yellow_max =~ ^[1-9][0-9]*$ ]] || yellow_max=400000
    if ((used < green_max)); then
      c=$GREEN
    elif ((used < yellow_max)); then
      c=$YELLOW
    else c=$RED; fi

    # % is a session-wrap budget, not a fraction of the context window:
    # 100% == the top of yellow (yellow_max), the point to seriously consider
    # a fresh session. Past that it intentionally reads >100% (and red),
    # since degradation scales with how big the context blob gets.
    pct=$((used * 100 / yellow_max))

    ctx_seg="${DIM}ctx ${UNDIM}${c}$(fmt_tokens "$used") (${pct}%)${RST}"
  fi
fi

# --- cost -------------------------------------------------------------
cost_seg=""
if [[ -n $cost ]]; then
  cost_seg="${DIM}\$$(printf '%.2f' "$cost" 2>/dev/null)${RST}"
fi

# --- assemble -----------------------------------------------------------------
right=""
for s in "$model_seg" "$ctx_seg" "$cost_seg"; do
  [[ -n $s ]] && right+="${right:+  }$s"
done

line="${cwd_seg}${git_seg}"
[[ -n $right ]] && line+="   ${DIM}│${UNDIM}   ${right}"

printf '%s' "$line"
