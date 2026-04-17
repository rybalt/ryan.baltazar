-- rb.homepage — a "start of day" dashboard showing open GitHub PRs across
-- every host authenticated via `gh auth`.
--
-- Fetching is async: the buffer opens instantly with per-host "Loading…"
-- placeholders, one GraphQL call fires per host in parallel, and the
-- buffer re-renders when every host has returned.
--
-- Triggered three ways:
--   1. `:Homepage` command (registered via M.setup)
--   2. `neovide +Homepage` or `nvim +Homepage`
--   3. Programmatically: `require("rb.homepage").open()`
--
-- Example shell alias:
--     alias nvd='neovide +Homepage'

local M = {}

-- ── Module state ─────────────────────────────────────────────────────────

-- Single reused buffer for the dashboard. q (:bdelete) invalidates it;
-- next M.open() creates a new one via ensure_buf().
local homepage_buf = nil

-- Coalesce flag: while true, additional M.open() calls no-op. Cleared
-- after the render completes. If the buffer is closed mid-fetch, the
-- callback silently skips render and leaves in_flight as-is — the
-- entry check in M.open also validates the buffer, so a stuck true
-- doesn't block a fresh invocation.
local in_flight = false

-- ── GraphQL query ────────────────────────────────────────────────────────
-- One call per host returns all three sections plus reviewDecision and
-- review-thread resolved state. See:
--   https://docs.github.com/en/graphql/reference/objects#pullrequest

local GRAPHQL_QUERY = [[
fragment PR on PullRequest {
  number
  title
  url
  isDraft
  repository { nameWithOwner }
  reviewDecision
  reviewThreads(first: 50) { nodes { isResolved } }
}

query {
  authored: viewer {
    pullRequests(states: OPEN, first: 50, orderBy: { field: UPDATED_AT, direction: DESC }) {
      nodes { ...PR }
    }
  }
  reviewRequested: search(query: "is:pr is:open review-requested:@me", type: ISSUE, first: 50) {
    nodes { ... on PullRequest { ...PR } }
  }
  assigned: search(query: "is:pr is:open assignee:@me", type: ISSUE, first: 50) {
    nodes { ... on PullRequest { ...PR } }
  }
}
]]

-- ── Host discovery ───────────────────────────────────────────────────────

-- Synchronous. `gh auth status` is fast (~100ms) and we need the list
-- before firing the per-host fetches.
local function list_hosts()
  local result = vim.system({ "gh", "auth", "status" }, { text = true }):wait()
  if result.code ~= 0 then
    local err = (result.stderr or "") .. (result.stdout or "")
    return { "github.com" }, "gh auth status failed: " .. vim.trim(err)
  end

  local hosts, seen = {}, {}
  for host in (result.stdout or ""):gmatch("Logged in to (%S+)") do
    if not seen[host] then
      seen[host] = true
      table.insert(hosts, host)
    end
  end

  if #hosts == 0 then
    return { "github.com" }, "no authenticated hosts parsed from gh auth status"
  end
  return hosts, nil
end

-- ── Async GraphQL fetch ──────────────────────────────────────────────────

-- Fires one `gh api graphql` call targeting `host` (via GH_HOST env).
-- callback(data, err) runs in libuv fast-event context — pure Lua ops
-- only; any Neovim API work must be wrapped in vim.schedule() by the caller.
local function fetch_graphql_async(host, callback)
  local cmd = { "gh", "api", "graphql", "-f", "query=" .. GRAPHQL_QUERY }

  -- Merge current env with GH_HOST override. vim.fn.environ() returns
  -- the full existing env as a table; we tack GH_HOST on top.
  local env = vim.fn.environ()
  if host then
    env.GH_HOST = host
  end

  vim.system(cmd, { text = true, env = env }, function(result)
    if result.code ~= 0 then
      callback(nil, (result.stderr or "") .. (result.stdout or ""))
      return
    end
    local ok, parsed = pcall(vim.json.decode, result.stdout)
    if not ok or type(parsed) ~= "table" or not parsed.data then
      callback(nil, "graphql parse failed: " .. (result.stdout or ""))
      return
    end
    callback(parsed.data, nil)
  end)
end

-- ── Rendering helpers ────────────────────────────────────────────────────

local function unresolved_count(pr)
  local n = 0
  if pr.reviewThreads and pr.reviewThreads.nodes then
    for _, t in ipairs(pr.reviewThreads.nodes) do
      if not t.isResolved then n = n + 1 end
    end
  end
  return n
end

-- All tokens padded to 10 chars wide so PR rows align.
local function status_token(pr)
  if pr.isDraft then return "[DRAFT]   " end
  local dec = pr.reviewDecision
  if dec == "APPROVED"          then return "[APPROVED]" end
  if dec == "CHANGES_REQUESTED" then return "[CHANGES] " end
  -- REVIEW_REQUIRED or nil
  return "[AWAITING]"
end

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

local function render_section(lines, pr_urls, title, prs)
  table.insert(lines, "")
  table.insert(lines, string.format("    %s (%d)", title, #prs))
  table.insert(lines, "")
  if #prs == 0 then
    table.insert(lines, "      (none)")
    return
  end
  for _, pr in ipairs(prs) do
    local repo = (pr.repository and pr.repository.nameWithOwner) or "?"
    table.insert(lines,
      string.format("      %s  %s#%d  %s  (%d unresolved)",
        status_token(pr), repo, pr.number, pr.title, unresolved_count(pr)))
    pr_urls[#lines] = pr.url
  end
end

local function render_host(lines, pr_urls, host_entry)
  table.insert(lines, "")
  table.insert(lines, string.format("  ━━━ %s ━━━", host_entry.name))

  -- Dedupe reset per host: PR URLs are per-server, can't collide across hosts.
  local seen = {}
  render_section(lines, pr_urls, "AUTHORED",         dedupe(host_entry.data.authored, seen))
  render_section(lines, pr_urls, "REVIEW REQUESTED", dedupe(host_entry.data.review,   seen))
  render_section(lines, pr_urls, "ASSIGNED",         dedupe(host_entry.data.assigned, seen))

  if #host_entry.data.errors > 0 then
    table.insert(lines, "")
    table.insert(lines, "    WARNINGS:")
    for _, e in ipairs(host_entry.data.errors) do
      -- Errors may be multi-line (e.g. GraphQL error payloads); split.
      for line in vim.trim(e):gmatch("[^\r\n]+") do
        table.insert(lines, "      " .. line)
      end
    end
  end
end

-- ── Buffer management ────────────────────────────────────────────────────

local function is_dashboard_open()
  return homepage_buf and vim.api.nvim_buf_is_valid(homepage_buf)
end

local function ensure_buf()
  if is_dashboard_open() then return homepage_buf end
  homepage_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[homepage_buf].bufhidden = "hide"
  vim.bo[homepage_buf].filetype  = "homepage"
  return homepage_buf
end

local function write_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly   = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly   = true
end

local function bind_keymaps(buf, pr_urls)
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
  kmap("q", "<cmd>bdelete<cr>",       "Close homepage")
  kmap("R", function() M.open() end,  "Refresh homepage")
end

local function show_skeleton(buf, hosts, host_err)
  local lines = {
    "  GitHub Homepage",
    "  ═══════════════",
    "",
    "  <CR> open in browser   |   R refresh   |   q close",
  }
  if host_err then
    table.insert(lines, "")
    table.insert(lines, "  WARNING: " .. host_err)
  end
  for _, host in ipairs(hosts) do
    table.insert(lines, "")
    table.insert(lines, string.format("  ━━━ %s ━━━", host))
    table.insert(lines, "    Loading…")
  end

  write_lines(buf, lines)
  -- Bind keymaps with empty pr_urls: <CR> is a no-op during skeleton;
  -- q and R already work. render_into will rebind with live URLs.
  bind_keymaps(buf, {})

  -- Silent buffer switch avoids BufWinEnter autocmd chatter that can
  -- overflow cmdline and trigger the "Press ENTER" hit-enter prompt.
  vim.cmd("silent! buffer " .. buf)
end

local function render_into(buf, data)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = {
    "  GitHub Homepage",
    "  ═══════════════",
    "",
    "  <CR> open in browser   |   R refresh   |   q close",
  }
  local pr_urls = {}

  if data.host_list_error then
    table.insert(lines, "")
    table.insert(lines, "  WARNING: " .. data.host_list_error)
  end

  for _, host_entry in ipairs(data.hosts) do
    render_host(lines, pr_urls, host_entry)
  end

  write_lines(buf, lines)
  bind_keymaps(buf, pr_urls)
end

-- ── Public API ───────────────────────────────────────────────────────────

function M.open()
  -- Coalesce: if a fetch is already running AND the dashboard is still
  -- visible, ignore the request. If the dashboard was closed mid-fetch
  -- (q + :Homepage), proceed — the stale callbacks will silently no-op
  -- on the old invalid buffer.
  if in_flight and is_dashboard_open() then return end
  in_flight = true

  local hosts, host_err = list_hosts()
  local buf = ensure_buf()
  show_skeleton(buf, hosts, host_err)

  -- Pre-seed result slots; each callback writes exactly one slot.
  local host_results = {}
  local pending = #hosts

  for _, host in ipairs(hosts) do
    fetch_graphql_async(host, function(data, err)
      if data then
        host_results[host] = {
          authored = (data.authored and data.authored.pullRequests and data.authored.pullRequests.nodes) or {},
          review   = (data.reviewRequested and data.reviewRequested.nodes) or {},
          assigned = (data.assigned and data.assigned.nodes) or {},
          errors   = {},
        }
      else
        host_results[host] = { authored = {}, review = {}, assigned = {}, errors = { err or "unknown error" } }
      end

      pending = pending - 1
      if pending == 0 then
        -- Marshal to the main thread before touching Neovim APIs.
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(buf) then
            local assembled = { hosts = {}, host_list_error = host_err }
            for _, h in ipairs(hosts) do
              table.insert(assembled.hosts, { name = h, data = host_results[h] })
            end
            render_into(buf, assembled)
            in_flight = false
          end
          -- If buf was deleted mid-fetch, leave in_flight alone; the
          -- entry check in M.open validates the buffer so a stuck-true
          -- in_flight doesn't block a fresh start.
        end)
      end
    end)
  end
end

function M.setup()
  vim.api.nvim_create_user_command("Homepage", function()
    M.open()
  end, { desc = "Open the GitHub PR homepage dashboard" })
end

return M
