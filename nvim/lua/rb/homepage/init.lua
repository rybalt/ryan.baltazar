-- rb.homepage — a minimal "start of day" dashboard showing my open GitHub PRs.
--
-- Demonstrates the fundamentals of writing a custom Neovim module:
--   • how a Lua module's public API looks (returned table `M`)
--   • creating a buffer, setting its options, writing lines
--   • registering a user command (`:Homepage`)
--   • buffer-local keymaps (<CR>, q, R)
--   • shelling out to an external CLI (`gh`) via `vim.system`
--   • parsing JSON into Lua tables
--
-- Triggered three ways:
--   1. `:Homepage` command (registered via M.setup)
--   2. `neovide +Homepage` or `nvim +Homepage`   (Neovim's built-in
--      "run this command on VimEnter" syntax — acts like a CLI flag)
--   3. Programmatically: `require("rb.homepage").open()`
--
-- Example shell alias:
--     alias nvd='neovide +Homepage'

local M = {}

-- ── Data fetching ────────────────────────────────────────────────────────
-- Fields we ask gh to return per PR. Only the ones we render.
-- (Full schema: `gh search prs --json`.)
local FIELDS = table.concat({
  "number", "title", "url",
  "repository", "isDraft", "state",
  "author", "labels", "createdAt", "updatedAt",
}, ",")

-- Run one `gh search prs` invocation. query_args is a list of extra flags
-- like {"--author=@me"} appended to the base command.
-- Returns parsed Lua table, or nil + error message.
local function fetch_prs(query_args)
  local cmd = {
    "gh", "search", "prs",
    "--state=open",
    "--limit=50",
    "--json=" .. FIELDS,
  }
  vim.list_extend(cmd, query_args)

  -- vim.system: modern argv-style process spawn; no shell quoting needed.
  -- :wait() blocks until exit; text=true decodes stdout/stderr as strings.
  local result = vim.system(cmd, { text = true }):wait()

  if result.code ~= 0 then
    return nil, (result.stderr or "") .. (result.stdout or "")
  end

  local ok, parsed = pcall(vim.json.decode, result.stdout)
  if not ok or type(parsed) ~= "table" then
    return nil, "json parse failed: " .. (result.stdout or "")
  end
  return parsed
end

-- Fetch all three sections. Accumulates errors rather than failing on the
-- first — we want to render whatever works.
local function fetch_all()
  local authored, err_a = fetch_prs({ "--author=@me" })
  local review,   err_r = fetch_prs({ "--review-requested=@me" })
  local assigned, err_s = fetch_prs({ "--assignee=@me" })
  return {
    authored = authored or {},
    review   = review or {},
    assigned = assigned or {},
    errors = vim.tbl_filter(function(e) return e ~= nil end, { err_a, err_r, err_s }),
  }
end

-- Dedupe by PR url (authored+assigned often overlap).
local function dedupe(prs, seen)
  local out = {}
  for _, pr in ipairs(prs) do
    if not seen[pr.url] then
      seen[pr.url] = true
      table.insert(out, pr)
    end
  end
  return out
end

-- ── Rendering ────────────────────────────────────────────────────────────

-- Short status token in front of each PR.
-- TODO: richer status (APPROVED / CHANGES_REQUESTED / AWAITING) requires
-- `gh api graphql` with a custom query; `gh search prs` doesn't expose
-- reviewDecision. Same deal for unresolved-thread counts.
local function status_token(pr)
  if pr.isDraft then return "[DRAFT] " end
  return "[OPEN]  "
end

-- Append one section's heading and rows to `lines`; track URL per line.
local function render_section(lines, pr_urls, title, prs)
  table.insert(lines, "")
  table.insert(lines, string.format("  %s (%d)", title, #prs))
  table.insert(lines, "")
  if #prs == 0 then
    table.insert(lines, "    (none)")
    return
  end
  for _, pr in ipairs(prs) do
    local repo = (pr.repository and pr.repository.nameWithOwner) or "?"
    table.insert(lines,
      string.format("    %s%s#%d  %s",
        status_token(pr), repo, pr.number, pr.title))
    pr_urls[#lines] = pr.url
  end
end

-- Create the buffer, render into it, set keymaps, make it current.
local function render(data)
  -- nvim_create_buf(false, true) already implies buftype=nofile + no swap.
  -- Use bufhidden=hide rather than wipe: snacks' BufWinEnter handlers race
  -- with wipe and can see an invalid buffer id while processing.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype  = "homepage"  -- hook for future syntax highlighting

  local lines = {}
  local pr_urls = {}  -- line_number → URL, for <CR>

  table.insert(lines, "  GitHub Homepage")
  table.insert(lines, "  ═══════════════")
  table.insert(lines, "")
  table.insert(lines, "  <CR> open in browser   |   R refresh   |   q close")

  -- Dedupe across sections (authored ∩ assigned is common).
  local seen = {}
  render_section(lines, pr_urls, "AUTHORED",         dedupe(data.authored, seen))
  render_section(lines, pr_urls, "REVIEW REQUESTED", dedupe(data.review,   seen))
  render_section(lines, pr_urls, "ASSIGNED",         dedupe(data.assigned, seen))

  if #data.errors > 0 then
    table.insert(lines, "")
    table.insert(lines, "  WARNINGS:")
    for _, e in ipairs(data.errors) do
      table.insert(lines, "    " .. vim.trim(e))
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly   = true

  -- Buffer-local keymaps.
  local kmap = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end

  kmap("<CR>", function()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local url = pr_urls[lnum]
    if url then
      -- macOS. Linux: "xdg-open". Windows: "start".
      vim.fn.jobstart({ "open", url }, { detach = true })
    end
  end, "Open PR in browser")

  kmap("q", "<cmd>bdelete<cr>",        "Close homepage")
  kmap("R", function() M.open() end,   "Refresh homepage")

  vim.api.nvim_set_current_buf(buf)
end

-- ── Public API ───────────────────────────────────────────────────────────

function M.open()
  vim.notify("Fetching GitHub PRs via gh…", vim.log.levels.INFO)
  local data = fetch_all()
  render(data)
  -- Clear the "Fetching…" message from the cmdline area now that we're done.
  -- (vim.notify lingers in classic cmdline until overwritten.)
  vim.api.nvim_echo({ { "" } }, false, {})
end

function M.setup()
  vim.api.nvim_create_user_command("Homepage", function()
    M.open()
  end, { desc = "Open the GitHub PR homepage dashboard" })
end

return M
