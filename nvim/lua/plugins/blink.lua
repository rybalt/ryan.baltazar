-- blink.cmp keymap preset: <Tab> / <S-Tab> drive completion + snippet
-- navigation, with a literal-tab fallback when there's nothing to complete.
--
-- Auto-show policy: debounced + prefix-gated.
--   - Menu only auto-shows when the current word is >= MIN_PREFIX chars.
--   - AND when the user has paused typing for at least DELAY_MS.
--   - Trigger characters (".", "->", etc.) still show immediately via
--     blink's separate `trigger.show_on_trigger_character` path.
--   - <C-Space> always manually triggers the menu regardless of gates.
--
-- Performance notes: the TextChangedI autocmd runs on every keystroke
-- in insert mode. Steady-state per-keystroke cost is kept minimal:
--   - Module references captured as upvalues at config time
--   - schedule_wrap wrapper created once, reused for every timer fire
--   - Byte-range keyword predicate (no regex engine, no substring alloc)
--   - Early exit before allocating the line string when col < MIN_PREFIX
--   - Loop is O(MIN_PREFIX), independent of line length
-- Net: 1 small table + 1 line string per keystroke; no regex; no closure
-- churn. Safe for very fast typing or very long lines.

local MIN_PREFIX = 3
local DELAY_MS   = 250

return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = { preset = "super-tab" },
      completion = {
        menu = {
          -- Disable blink's built-in keyword auto-show; replaced by the
          -- debounced trigger below. Trigger-character auto-show still
          -- works independently (controlled by completion.trigger.*).
          auto_show = false,
        },
      },
    },

    config = function(_, opts)
      require("blink.cmp").setup(opts)

      -- ── Upvalues (captured once at config time) ─────────────────────
      local blink             = require("blink.cmp")
      local api_get_line      = vim.api.nvim_get_current_line
      local api_get_cursor    = vim.api.nvim_win_get_cursor
      local mode              = vim.fn.mode

      -- Single reused libuv timer. stop()/start() cycle per keystroke;
      -- no allocation in the timer machinery itself. new_timer() only
      -- returns nil in pathological cases (loop shutdown, OOM); assert
      -- so failures surface at plugin load rather than mysteriously later.
      ---@type uv_timer_t
      local timer = assert(vim.uv.new_timer(), "rb.blink: failed to allocate timer")

      -- schedule_wrap called ONCE here; the wrapper function is reused
      -- by every timer:start() call below, not re-allocated per keystroke.
      local on_fire = vim.schedule_wrap(function()
        if mode() == "i" then
          blink.show()
        end
      end)

      -- Byte-range keyword predicate. Faster than `char:match("[%w_]")`
      -- because it avoids regex engine setup and substring allocation.
      -- ASCII-only — fine for C#/C++/Lua/Python identifiers.
      local function is_keyword_byte(b)
        return (b >= 48 and b <= 57)    -- 0-9
            or (b >= 65 and b <= 90)    -- A-Z
            or (b >= 97 and b <= 122)   -- a-z
            or b == 95                  -- _
      end

      -- Constant-work prefix check:
      --   - Bails before get_current_line() when col is too small for a prefix.
      --   - Inspects at most MIN_PREFIX bytes regardless of line length.
      -- The expensive part (nvim_get_current_line copying the line into Lua)
      -- is skipped entirely when col < MIN_PREFIX, which covers most early
      -- keystrokes after entering insert mode or after typing whitespace.
      local function has_min_prefix()
        local col = api_get_cursor(0)[2]  -- 0-indexed byte column
        if col < MIN_PREFIX then
          return false
        end

        local line = api_get_line()
        -- Check the last MIN_PREFIX bytes before the cursor.
        for i = col - MIN_PREFIX + 1, col do
          if not is_keyword_byte(line:byte(i)) then
            return false
          end
        end
        return true
      end

      vim.api.nvim_create_autocmd("TextChangedI", {
        group = vim.api.nvim_create_augroup("rb_blink_debounce", { clear = true }),
        callback = function()
          -- If the menu is already up, blink's own filter-on-type handles
          -- updates; don't re-trigger show() and risk flicker.
          if blink.is_visible and blink.is_visible() then
            return
          end

          if not has_min_prefix() then
            timer:stop()
            return
          end

          -- Reset the debounce window. Each keystroke restarts the timer;
          -- only the last keystroke's timer fires on_fire after DELAY_MS.
          timer:stop()
          timer:start(DELAY_MS, 0, on_fire)
        end,
      })
    end,
  },
}
