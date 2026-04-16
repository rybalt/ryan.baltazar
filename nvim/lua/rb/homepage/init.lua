-- rb.homepage — a minimal "start of day" dashboard showing my open GitHub PRs
-- across every host authenticated via `gh auth`.
--
-- Demonstrates the fundamentals of writing a custom Neovim module:
--   • how a Lua module's public API looks (returned table `M`)
--   • creating a buffer, setting its options, writing lines
--   • registering a user command (`:Homepage`)
--   • buffer-local keymaps (<CR>, q, R)
--   • shelling out to an external CLI (`gh`) via `vim.system`
--   • parsing JSON into Lua tables
--   • overriding a subprocess's environment to target multiple gh hosts
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

-- ── Host discovery ───────────────────────────────────────────────────────
-- `gh auth status` prints something like:
--     github.com
--       ✓ Logged in to github.com account rybalt (keyring)
--       ...
--     github.enterprise.example.com
--       ✓ Logged in to github.enterprise.example.com account rbaltazar (...)
--       ...
--
-- No --json flag exists for this subcommand, so we parse the human output.
-- We match `Logged in to <host>` lines and dedupe, preserving order.
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

-- ── Data fetching ────────────────────────────────────────────────────────
-- Fields we ask gh to return per PR. Only the ones we render.
-- (Full schema: `gh search prs --json`.)
local FIELDS = table.concat({
  "number", "title", "url",
  "repository", "isDraft", "state",
  "author", "labels", "createdAt", "updatedAt",
}, ",")

-- Run one `gh search prs` invocation against a specific host.
-- query_args is a list of extra flags like {"--author=@me"}.
-- host sets GH_HOST for the subprocess so gh targets the right GitHub.
-- Returns parsed Lua table, or nil + error message.
local function fetch_prs(query_args, host)
  local cmd = {
    "gh", "search", "prs",
    "--state=open",
    "--limit=50",
    "--json=" .. FIELDS,
  }
  vim.list_extend(cmd, query_args)

  -- Merge current process env with a GH_HOST override. vim.fn.environ()
  -- returns the full existing env as a table; we tack GH_HOST on top.
  local env = vim.fn.environ()
  if host then
    env.GH_HOST = host
  end

  -- vim.system: modern argv-style process spawn; no shell quoting needed.
  -- :wait() blocks until exit; text=true decodes stdout/stderr as strings.
  local result = vim.system(cmd, { text = true, env = env }):wait()

  if result.code ~= 0 then
    return nil, (result.stderr or "") .. (result.stdout or "")
  end

  local ok, parsed = pcall(vim.json.decode, result.stdout)
  if not ok or type(parsed) ~= "table" then
    return nil, "json parse failed: " .. (result.stdout or "")
  end
  return parsed
end

-- Fetch the three sections for one host. Accumulates errors rather than
-- failing on the first — we want to render whatever works.
local function fetch_for_host(host)
  local authored, err_a = fetch_prs({ "--author=@me" },           host)
  local review,   err_r = fetch_prs({ "--review-requested=@me" }, host)
  local assigned, err_s = fetch_prs({ "--assignee=@me" },         host)
  return {
    authored = authored or {},
    review   = review or {},
    assigned = assigned or {},
    errors = vim.tbl_filter(function(e) return e ~= nil end, { err_a, err_r, err_s }),
  }
end

-- Top-level fetch: enumerate hosts, then fetch each. Returns an ordered
-- list so the dashboard renders hosts in the order `gh auth status`
-- listed them.
local function fetch_all()
  local hosts, host_err = list_hosts()
  local results = {}
  for _, host in ipairs(hosts) do
    table.insert(results, { name = host, data = fetch_for_host(host) })
  end
  return {
    hosts = results,
    host_list_error = host_err,
  }
end

-- Dedupe by PR url (authored+assigned often overlap within a host).
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
  table.insert(lines, string.format("    %s (%d)", title, #prs))
  table.insert(lines, "")
  if #prs == 0 then
    table.insert(lines, "      (none)")
    return
  end
  for _, pr in ipairs(prs) do
    local repo = (pr.repository and pr.repository.nameWithOwner) or "?"
    table.insert(lines,
      string.format("      %s%s#%d  %s",
        status_token(pr), repo, pr.number, pr.title))
    pr_urls[#lines] = pr.url
  end
end

-- Render one host's block (header + three sections + per-host warnings).
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
      table.insert(lines, "      " .. vim.trim(e))
    end
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

  if data.host_list_error then
    table.insert(lines, "")
    table.insert(lines, "  WARNING: " .. data.host_list_error)
  end

  for _, host_entry in ipairs(data.hosts) do
    render_host(lines, pr_urls, host_entry)
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

  -- Silent wrapper suppresses autocmd chatter that can overflow cmdline
  -- and trigger Neovim's "Press ENTER to continue" hit-enter prompt.
  vim.cmd("silent! buffer " .. buf)
end

-- ── Public API ───────────────────────────────────────────────────────────

function M.open()
  local data = fetch_all()
  render(data)
end

function M.setup()
  vim.api.nvim_create_user_command("Homepage", function()
    M.open()
  end, { desc = "Open the GitHub PR homepage dashboard" })
end

return M
