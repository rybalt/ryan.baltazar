-- Port the fish prompt's path & branch shortening policies to lualine.
-- See /Users/ryan/src/rybalt/fish/conf.d/rb-prompt.fish:224-259 for the
-- originals. Two policies layered via `fmt` callbacks on existing LazyVim
-- components — no replacement of root_dir/pretty_path internals:
--
--   1. Workspace root name (lualine_c via LazyVim.lualine.root_dir()):
--      collapse each `.`/`-`-separated segment to its first char when the
--      name is > ROOT_ABBREVIATE_THRESHOLD chars long.
--         com.unity.xr.hands  → c.u.x.h
--         clever-hawking-6bb  → c-h-6
--         rybalt              → rybalt   (under threshold, untouched)
--
--   2. Branch name (lualine_b "branch"): middle-ellipsize when 3+ slash
--      segments. The leaf is sacred.
--         rybalt/hand-extensibility/050-foo  → rybalt/…/050-foo
--         feature/login                      → feature/login
--
-- Both helpers are pure, allocation-light, and safe to run every redraw.
return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local function abbreviate_dot_hyphen(name)
        -- Capture the first char of each `.`/`-`-separated run, replace
        -- the run with just that char. `%-` escapes the literal hyphen
        -- inside the Lua char class.
        return (name:gsub("([^.%-])[^.%-]+", "%1"))
      end

      local function compress_branch(branch)
        if branch == nil or branch == "" then return branch end
        local first, last, count = nil, nil, 0
        for part in branch:gmatch("[^/]+") do
          count = count + 1
          if count == 1 then first = part end
          last = part
        end
        if count < 3 then return branch end
        return first .. "/…/" .. last
      end

      -- Branch (lualine_b): bare "branch" → { "branch", fmt = ... }
      for i, c in ipairs(opts.sections.lualine_b or {}) do
        if c == "branch" then
          opts.sections.lualine_b[i] = { "branch", fmt = compress_branch }
        elseif type(c) == "table" and c[1] == "branch" then
          c.fmt = compress_branch
        end
      end

      -- Root dir (lualine_c): LazyVim.lualine.root_dir() returns a spec
      -- table with `name` and its own `fmt` (which prepends an icon).
      -- We wrap that fmt so the icon stays and our abbreviation runs
      -- against the formatted string, mirroring the fish helper's
      -- "string.replace on the formatted PWD" approach.
      local ROOT_ABBREVIATE_THRESHOLD = 8
      for _, c in ipairs(opts.sections.lualine_c or {}) do
        if type(c) == "table" and c.name ~= nil then
          local prev_fmt = c.fmt
          c.fmt = function(str)
            local base = type(c.name) == "function" and c.name() or c.name
            if base and #base > ROOT_ABBREVIATE_THRESHOLD then
              local abbr = abbreviate_dot_hyphen(base)
              str = str:gsub(vim.pesc(base), abbr, 1)
            end
            if prev_fmt then str = prev_fmt(str) end
            return str
          end
        end
      end

      return opts
    end,
  },
}
