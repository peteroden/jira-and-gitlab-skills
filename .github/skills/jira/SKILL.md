---
name: jira
description: >
  Manage Jira issues — create tickets, update stories, search with JQL,
  move issues between statuses, add comments, look up issue details.
  Use this when you need to create a Jira ticket, update a Jira issue,
  transition an issue to Done/In Progress, search for issues assigned to
  someone, find bugs in a sprint, check issue status, or post a comment.
  Works with both Jira Cloud and Jira Server/Data Center.
---

## Prerequisites

The script at `.github/skills/jira/jira` requires `python3` (3.6+).

**Environment variables** (must be set before running any command):

| Variable | When required | Purpose |
|----------|--------------|---------|
| `JIRA_BASE_URL` | Always | Jira instance URL (e.g., `https://company.atlassian.net`) |
| `JIRA_USER_EMAIL` | Cloud | Account email for basic auth |
| `JIRA_API_TOKEN` | Cloud | API token paired with email |
| `JIRA_PAT` | Server/DC | Personal access token (bearer auth) |

Auth is auto-detected: if `JIRA_PAT` is set → Server/DC bearer auth. Otherwise → Cloud basic auth with email + token.

If a command fails with `JIRA_BASE_URL is not set`, verify the env vars are exported in the current shell.

## Output Modes

All read commands (`search`, `get`, `comments`) support a `--fields` flag that extracts specific fields using dot-notation, outputting tab-separated values instead of raw JSON. **Always use `--fields` by default** to keep output concise:

```bash
.github/skills/jira/jira search 'assignee = currentUser()' --fields key,fields.summary,fields.status.name
.github/skills/jira/jira get PROJ-123 --fields key,fields.summary,fields.status.name,fields.assignee.displayName
.github/skills/jira/jira comments PROJ-123 PROJ-456 --fields _issue,author.displayName,created,body
```

For lists, output includes a header row. For single items, output is `field: value` per line. Nested fields use dot-notation (e.g. `fields.status.name`). Omit `--fields` only when the full JSON is needed.

## Command Reference

All commands use the full path: `.github/skills/jira/jira <command> [args...]`

| Command | Purpose | Syntax |
|---------|---------|--------|
| `search` | Find issues via JQL | `.github/skills/jira/jira search '<jql>' [max_results]` |
| `get` | Fetch a single issue | `.github/skills/jira/jira get <ISSUE-KEY>` |
| `create` | Create a new issue | `.github/skills/jira/jira create '<json>'` |
| `update` | Update issue fields | `.github/skills/jira/jira update <ISSUE-KEY> '<json>'` |
| `transition` | Change issue status | `.github/skills/jira/jira transition <ISSUE-KEY> '<status>'` |
| `comment` | Add a comment | `.github/skills/jira/jira comment <ISSUE-KEY> '<body>'` |
| `comments` | List comments on issues | `.github/skills/jira/jira comments <ISSUE-KEY> [ISSUE-KEY ...]` |
| `fields` | Discover issue types & fields | `.github/skills/jira/jira fields <PROJECT-KEY> [issue-type-id]` |

## Workflows

### Look Up an Issue

```bash
.github/skills/jira/jira get PROJ-123
```

Output: full issue JSON including key, summary, description, status, assignee, priority, labels, and comments.

### Search for Issues

```bash
.github/skills/jira/jira search 'project = PROJ AND status = "In Progress"'
.github/skills/jira/jira search 'assignee = currentUser() ORDER BY updated DESC' 10
```

**Important (Cloud):** The new search API requires a bounded query. Always include a `project`, `assignee`, or other filter — bare `ORDER BY` queries will fail.

### Create an Issue (Step-by-Step)

**Step 1 — Discover issue types:**
```bash
.github/skills/jira/jira fields PROJ
```
Output includes issue type IDs. Find the one you need (e.g., Task → `10045`).

**Step 2 — Discover required fields for that issue type:**
```bash
.github/skills/jira/jira fields PROJ 10045
```
Look at `"required": true` fields in the response. Every project may have custom required fields beyond the standard ones.

**Step 3 — Build the JSON payload and create:**
```bash
.github/skills/jira/jira create '{
  "fields": {
    "project": { "key": "PROJ" },
    "summary": "Short description of the issue",
    "issuetype": { "name": "Task" }
  }
}'
```

Output: `{ "id": "...", "key": "PROJ-42", "self": "..." }`

### Update an Issue

Only include fields you want to change:

```bash
.github/skills/jira/jira update PROJ-123 '{
  "fields": {
    "summary": "Updated summary",
    "priority": { "name": "High" },
    "labels": ["backend", "urgent"]
  }
}'
```

**Note:** You cannot change `status` via update — use `transition` instead.

### Transition an Issue (Change Status)

Use a transition name (e.g., "In Progress", "Done") or a transition ID:

```bash
.github/skills/jira/jira transition PROJ-123 "In Progress"
.github/skills/jira/jira transition PROJ-123 "Done"
```

If the transition name is not found, the script lists available transitions in the error output.

### Add a Comment

```bash
.github/skills/jira/jira comment PROJ-123 "PR #42 addresses this issue."
```

Or pipe from stdin:
```bash
echo "Deployed to staging." | .github/skills/jira/jira comment PROJ-123
```

## JSON Field Reference

### Common Field Patterns

| Field | JSON format |
|-------|-------------|
| `project` | `{ "key": "PROJ" }` |
| `issuetype` | `{ "name": "Task" }` or `{ "name": "Bug" }` |
| `summary` | `"Short description"` |
| `description` | `"Detailed description"` |
| `priority` | `{ "name": "High" }` — values: Highest, High, Medium, Low, Lowest |
| `assignee` | `{ "accountId": "5e..." }` (Cloud) or `{ "name": "jsmith" }` (Server) |
| `labels` | `["backend", "security"]` |
| `components` | `[{ "name": "API" }]` |
| Custom fields | `"customfield_10001": "value"` — use `fields` command to discover |

### Full Create Example

```json
{
  "fields": {
    "project": { "key": "PROJ" },
    "summary": "Fix login timeout on mobile",
    "issuetype": { "name": "Bug" },
    "description": "Users on iOS report 30s timeout during OAuth flow.",
    "priority": { "name": "High" },
    "labels": ["mobile", "auth"],
    "components": [{ "name": "Authentication" }]
  }
}
```

## Common JQL Patterns

| Goal | JQL |
|------|-----|
| My open issues | `assignee = currentUser() AND resolution = Unresolved` |
| Sprint backlog | `project = PROJ AND sprint in openSprints()` |
| Recently updated | `project = PROJ AND updated >= -7d ORDER BY updated DESC` |
| Bugs by priority | `project = PROJ AND issuetype = Bug ORDER BY priority ASC` |
| Unassigned issues | `project = PROJ AND assignee is EMPTY` |
| Text search | `project = PROJ AND text ~ "login error"` |

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `JIRA_BASE_URL is not set` | Env vars not exported | Export all required env vars in current shell |
| `HTTP 401` | Bad credentials | Verify API token/PAT is correct and not expired |
| `HTTP 403` | Insufficient permissions | Check the token's project/scope permissions |
| `HTTP 404` | Wrong issue key or URL | Verify `JIRA_BASE_URL` and issue key exist |
| `HTTP 410` | Deprecated endpoint | You're hitting a removed Cloud API — update the script |
| `transition '...' not found` | Invalid transition name | Check available transitions with `get` (look at status) |
| `invalid issue key` | Key doesn't match `PROJ-123` format | Use uppercase project key + number |
| `python3 is required` | python3 not in PATH | Install python3 for your platform |
