local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- Appearance -----------------------------------------------------------
-- Follow the OS light/dark setting, mirroring ghostty + nvim: Catppuccin
-- Latte when light, Mocha when dark. Both the built-in color_scheme AND the
-- fancy tab bar switch per flavor — the tab bar frame is NOT part of a
-- color_scheme (it defaults dark), so it must be recolored explicitly or it
-- reads wrong under Latte. Active tab uses mauve to match the active-window
-- accent in tmux/.tmux.conf and the nvim cursor.
local flavors = {
  latte = {
    scheme = 'Catppuccin Latte',
    frame = '#e6e9ef', -- mantle
    active = { bg = '#eff1f5', fg = '#8839ef' }, -- base / mauve
    idle = { bg = '#e6e9ef', fg = '#6c6f85' }, -- mantle / subtext0
    hover = { bg = '#ccd0da', fg = '#4c4f69' }, -- surface0 / text
  },
  mocha = {
    scheme = 'Catppuccin Mocha',
    frame = '#181825', -- mantle
    active = { bg = '#1e1e2e', fg = '#cba6f7' }, -- base / mauve
    idle = { bg = '#181825', fg = '#a6adc8' }, -- mantle / subtext0
    hover = { bg = '#313244', fg = '#cdd6f4' }, -- surface0 / text
  },
}

-- A config fragment (scheme + frame + tab-bar cells) for the given flavor.
-- Reused for both the initial paint and the live-switch overrides. This owns
-- color_scheme + window_frame + colors wholesale — the live-switch handler
-- below replaces those tables outright on every flip, so any future palette
-- pinning (see PLAN.md "Colors") must route through here or it gets wiped.
local function fragment_for(appearance)
  local f = appearance:find 'Dark' and flavors.mocha or flavors.latte
  return {
    color_scheme = f.scheme,
    window_frame = { active_titlebar_bg = f.frame, inactive_titlebar_bg = f.frame },
    colors = {
      tab_bar = {
        active_tab = { bg_color = f.active.bg, fg_color = f.active.fg },
        inactive_tab = { bg_color = f.idle.bg, fg_color = f.idle.fg },
        inactive_tab_hover = { bg_color = f.hover.bg, fg_color = f.hover.fg },
        new_tab = { bg_color = f.idle.bg, fg_color = f.idle.fg },
        new_tab_hover = { bg_color = f.hover.bg, fg_color = f.hover.fg },
      },
    },
  }
end

-- Initial paint. wezterm.gui is nil when the config is evaluated headlessly
-- (e.g. shell-completion generation), so guard the lookup.
local initial = fragment_for(wezterm.gui and wezterm.gui.get_appearance() or 'Dark')
config.color_scheme = initial.color_scheme
config.window_frame = initial.window_frame
config.colors = initial.colors

-- Live follow: window-config-reloaded fires on the reload WezTerm triggers
-- when the OS appearance flips. Re-derive the fragment and push it through
-- per-window config overrides so the switch is live, no file write needed.
-- The guard also prevents an infinite loop: set_config_overrides re-fires
-- this event, and the ~= check short-circuits once the override matches.
-- (This also fires once right after initial config load, when overrides are
-- empty — it reapplies what config.* already set, once, then settles. Benign,
-- not a bug.)
wezterm.on('window-config-reloaded', function(window)
  local frag = fragment_for(window:get_appearance())
  local overrides = window:get_config_overrides() or {}
  if overrides.color_scheme ~= frag.color_scheme then
    overrides.color_scheme = frag.color_scheme
    overrides.window_frame = frag.window_frame
    overrides.colors = frag.colors
    window:set_config_overrides(overrides)
  end
end)

-- Tab bar ------------------------------------------------------------------
config.hide_tab_bar_if_only_one_tab = true

-- Inactive panes -----------------------------------------------------------
-- Disable WezTerm's default inactive-pane dimming ({ saturation = 0.9,
-- brightness = 0.8 }), which washes out every unfocused split. The old tmux
-- setup never dimmed inactive panes — it only accented the active one (the
-- mauve border in tmux/.tmux.conf) — so full-off is the faithful port. The
-- active tab bar + cursor already signal focus.
config.inactive_pane_hsb = { saturation = 1.0, brightness = 1.0 }

-- Font -------------------------------------------------------------------
config.font = wezterm.font 'FiraCode Nerd Font Mono'
config.font_size = 12

-- Terminal -----------------------------------------------------------------
config.scrollback_lines = 10000

-- Cursor -------------------------------------------------------------------
-- No blink — matches ghostty's cursor-style-blink = false.
config.default_cursor_style = 'SteadyBlock'

-- macOS Option key as Alt/Meta (ghostty: macos-option-as-alt = true, which
-- covers BOTH option keys; iTerm2: "Option Key Sends Esc+"). Left and right
-- Option both send a raw Esc-prefixed sequence instead of composing accented
-- characters — needed for readline/nvim meta-bindings.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Keybindings (tmux-mirror) -------------------------------------------------
-- leader = C-Space, matching the tmux prefix in tmux/.tmux.conf. Timeout
-- mirrors tmux's default: press leader, then the follow-up key within 1s.
config.leader = { key = 'Space', mods = 'CTRL', timeout_milliseconds = 1000 }

-- smart-splits handoff: one keystroke navigates BOTH nvim splits and WezTerm
-- panes. smart-splits.nvim (see nvim/lua/plugins/navigation.lua) sets the
-- IS_NVIM user var while nvim is focused and unsets it on exit. When it's set
-- we pass C-hjkl through to nvim — which moves its own split, or at the split
-- edge shells out to the WezTerm CLI to cross into the adjacent pane. When
-- it's unset (any non-nvim pane) we move the WezTerm pane directly. Without
-- this, an unconditional ActivatePaneDirection would swallow C-hjkl before
-- nvim ever sees it, so nvim's internal splits couldn't be reached.
local function is_nvim(pane)
  return pane:get_user_vars().IS_NVIM == 'true'
end

local pane_dirs = { h = 'Left', j = 'Down', k = 'Up', l = 'Right' }

local function nav(key)
  return {
    key = key,
    mods = 'CTRL',
    action = wezterm.action_callback(function(win, pane)
      if is_nvim(pane) then
        win:perform_action(act.SendKey { key = key, mods = 'CTRL' }, pane)
      else
        win:perform_action(act.ActivatePaneDirection(pane_dirs[key]), pane)
      end
    end),
  }
end

local keys = {
  -- tmux `prefix %` — split side-by-side.
  { key = '%', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  -- tmux `prefix "` — split stacked.
  { key = '"', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

  -- Pane nav without a leader, matching tmux's un-prefixed C-hjkl — with the
  -- smart-splits handoff (see nav()/is_nvim() above) so the same keys cross
  -- seamlessly between nvim splits and WezTerm panes.
  nav 'h',
  nav 'j',
  nav 'k',
  nav 'l',

  -- tmux `prefix C-Space` (send-prefix) — passthrough a literal C-Space to
  -- the program inside, since leader has already claimed the raw keystroke.
  { key = 'Space', mods = 'LEADER|CTRL', action = act.SendKey { key = 'Space', mods = 'CTRL' } },

  -- tmux `prefix e` — "editor layout": fresh tab, editor on the left
  -- (~60%), a vertically-stacked pair on the right, focus back on the left
  -- pane. No stock action composes multi-way splits, so this drives the mux
  -- API directly: spawn the tab, split its pane right for the column, split
  -- that column again for top/bottom, then refocus left.
  {
    key = 'e',
    mods = 'LEADER',
    action = wezterm.action_callback(function(window, pane)
      local _tab, left_pane = window:mux_window():spawn_tab {}
      local right_pane = left_pane:split { direction = 'Right', size = 0.4 }
      right_pane:split { direction = 'Bottom', size = 0.5 }
      left_pane:activate()
    end),
  },

  -- tmux `prefix E` reshapes the CURRENT window's panes into main-vertical
  -- via `select-layout main-vertical`. WezTerm has no preset-layout
  -- primitive to reflow an existing pane tree (only fresh splits) — see the
  -- "prefix E main-vertical reshape" DQ in wezterm/PLAN.md. Deferred;
  -- `prefix e` above covers the fresh-tab case.

  -- tmux `prefix >` / `<` — resize-pane -y 80%/20% (absolute). WezTerm's
  -- AdjustPaneSize is relative-only (grow/shrink by N cells), so this is an
  -- approximation: repeated presses walk toward the same intent rather than
  -- jumping straight to a fixed ratio.
  { key = '>', mods = 'LEADER', action = act.AdjustPaneSize { 'Down', 5 } },
  { key = '<', mods = 'LEADER', action = act.AdjustPaneSize { 'Up', 5 } },

  -- tmux `prefix {` / `}` (swap-pane -U/-D) — reorder panes. WezTerm has no
  -- directional "move this pane" action; RotatePanes cycles every pane around
  -- the layout, which for a two-pane split is exactly a swap.
  { key = '{', mods = 'LEADER', action = act.RotatePanes 'CounterClockwise' },
  { key = '}', mods = 'LEADER', action = act.RotatePanes 'Clockwise' },

  -- tmux-style targeted swap — overlay a letter on each pane, press one to
  -- swap it with the focused pane. Better than rotate when 3+ panes are open
  -- and you want to place a specific one.
  { key = '/', mods = 'LEADER', action = act.PaneSelect { mode = 'SwapWithActive' } },

  -- tmux `prefix |` — resize-pane -y 50% (absolute rebalance). WezTerm
  -- exposes no "set this pane to exactly N%" or "balance the tab" action —
  -- only the same relative AdjustPaneSize as above, which can't reliably
  -- reach 50/50 from an arbitrary starting ratio in one bound press.
  -- Deferred rather than shipping a fragile approximation; revisit if
  -- WezTerm adds a balance/equalize action.
  -- { key = '|', mods = 'LEADER', action = act.AdjustPaneSize { ... } },

  -- tmux `prefix c` — new tab, inheriting the current pane's cwd/domain.
  { key = 'c', mods = 'LEADER', action = act.SpawnTab 'CurrentPaneDomain' },

  -- tmux `prefix s` — session switcher. tmux sessions map to WezTerm
  -- workspaces, so this opens the launcher filtered to workspaces (fuzzy).
  -- Workspace *persistence* arrives with the mux domain in Diff 3; the
  -- switcher itself already works for in-GUI workspaces.
  { key = 's', mods = 'LEADER', action = act.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' } },

  -- tmux `prefix ,` — rename the current tab.
  {
    key = ',',
    mods = 'LEADER',
    action = act.PromptInputLine {
      description = 'Rename tab',
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:active_tab():set_title(line)
        end
      end),
    },
  },

  -- tmux `prefix z` — zoom the focused pane to fill the tab.
  { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },

  -- tmux `prefix x` — kill the focused pane (confirm to avoid fat-fingering
  -- a live process).
  { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },

  -- tmux `prefix r` — reload config in place (tmux/.tmux.conf's `bind r
  -- source-file`).
  { key = 'r', mods = 'LEADER', action = act.ReloadConfiguration },
}

-- tmux `prefix N` (base-index 1) — activate tab N. ActivateTab is
-- 0-indexed, so key '1' maps to index 0, …, key '9' maps to index 8.
for i = 1, 9 do
  table.insert(keys, {
    key = tostring(i),
    mods = 'LEADER',
    action = act.ActivateTab(i - 1),
  })
end

config.keys = keys

return config
