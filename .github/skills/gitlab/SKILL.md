---
name: gitlab
description: >
  Manage GitLab merge requests and CI/CD pipelines — create MRs, update MRs,
  add comments on merge requests, check pipeline status, read job logs, run
  pipelines, debug CI failures. Use this when you need to create a merge
  request, update an MR, comment on an MR, check if a pipeline passed or
  failed, read CI job output, trigger a pipeline run, or list jobs in a
  pipeline. Works with both GitLab.com and self-managed instances.
---

## Prerequisites

The script at `.github/skills/gitlab/gitlab` requires `python3` (3.6+).

**Environment variables** (must be set before running any command):

| Variable | Required | Purpose |
|----------|----------|---------|
| `GITLAB_URL` | Always | Instance URL (e.g., `https://gitlab.com` or `https://gitlab.company.com`) |
| `GITLAB_TOKEN` | Always | Personal access token (sent as `PRIVATE-TOKEN` header) |
| `GITLAB_PROJECT` | Optional | Project ID or URL-encoded path (e.g., `12345` or `group%2Fproject`) |

**Project auto-detection:** If `GITLAB_PROJECT` is not set, the script parses `git remote get-url origin` to extract the project path. This works for both SSH and HTTPS remotes. Set `GITLAB_PROJECT` explicitly when not in a git repo or targeting a different project.

## Output Modes

All read commands (`mr-list`, `mr-get`, `mr-notes`, `pipeline-get`, `pipeline-jobs`) support a `--fields` flag that extracts specific fields using dot-notation, outputting tab-separated values instead of raw JSON. **Always use `--fields` by default** to keep output concise:

```bash
.github/skills/gitlab/gitlab mr-list opened --fields iid,title,author.name,user_notes_count
.github/skills/gitlab/gitlab mr-get 42 --fields iid,title,state,source_branch,target_branch
.github/skills/gitlab/gitlab mr-notes 42 --fields author.name,created_at,body
```

For lists, output includes a header row. For single items, output is `field: value` per line. Nested fields use dot-notation (e.g. `author.name`). Omit `--fields` only when the full JSON is needed.

## Command Reference

All commands use the full path: `.github/skills/gitlab/gitlab <command> [args...]`

### Merge Requests

| Command | Purpose | Syntax |
|---------|---------|--------|
| `mr-list` | List merge requests | `.github/skills/gitlab/gitlab mr-list [state] [max]` |
| `mr-get` | Fetch MR details | `.github/skills/gitlab/gitlab mr-get <MR-IID>` |
| `mr-create` | Create a new MR | `.github/skills/gitlab/gitlab mr-create '<json>'` |
| `mr-update` | Update MR fields | `.github/skills/gitlab/gitlab mr-update <MR-IID> '<json>'` |
| `mr-comment` | Add a comment/note | `.github/skills/gitlab/gitlab mr-comment <MR-IID> '<body>'` |
| `mr-notes` | List MR comments | `.github/skills/gitlab/gitlab mr-notes <MR-IID> [max]` |

### Pipelines & Jobs

| Command | Purpose | Syntax |
|---------|---------|--------|
| `pipeline-get` | Get pipeline status | `.github/skills/gitlab/gitlab pipeline-get <PIPELINE-ID>` |
| `pipeline-run` | Run a pipeline on a branch | `.github/skills/gitlab/gitlab pipeline-run <BRANCH>` |
| `pipeline-jobs` | List jobs in a pipeline | `.github/skills/gitlab/gitlab pipeline-jobs <PIPELINE-ID>` |
| `job-log` | Read a job's log output | `.github/skills/gitlab/gitlab job-log <JOB-ID>` |

## Workflows

### List Merge Requests

```bash
.github/skills/gitlab/gitlab mr-list              # all MRs, last 20
.github/skills/gitlab/gitlab mr-list opened        # only open MRs
.github/skills/gitlab/gitlab mr-list merged 5      # last 5 merged MRs
```

State values: `all` (default), `opened`, `closed`, `merged`.

### Get Merge Request Details

```bash
.github/skills/gitlab/gitlab mr-get 42
```

Output: full MR JSON including title, description, state, source/target branches, author, reviewers, labels, and merge status.

### Create a Merge Request (Step-by-Step)

**Step 1 — Build the JSON payload:**

Required fields: `source_branch`, `target_branch`, `title`.

```bash
.github/skills/gitlab/gitlab mr-create '{
  "source_branch": "feature/add-auth",
  "target_branch": "main",
  "title": "feat(auth): add OAuth2 login"
}'
```

**Step 2 — Verify the MR was created:**

The response includes the MR IID. Use `mr-get` to confirm:
```bash
.github/skills/gitlab/gitlab mr-get 43
```

### Update a Merge Request

Only include fields you want to change:

```bash
.github/skills/gitlab/gitlab mr-update 42 '{
  "title": "fix(auth): resolve OAuth timeout",
  "description": "Increased timeout from 10s to 30s for token exchange.",
  "labels": "bug,auth"
}'
```

### Comment on a Merge Request

```bash
.github/skills/gitlab/gitlab mr-comment 42 "CI passed. Ready for review."
```

Or pipe from stdin:
```bash
echo "Addressed review feedback in latest commit." | .github/skills/gitlab/gitlab mr-comment 42
```

### Debug a Failed Pipeline (Step-by-Step)

**Step 1 — Get the pipeline status:**
```bash
.github/skills/gitlab/gitlab pipeline-get 12345
```
Look at `"status"` — values: `running`, `pending`, `success`, `failed`, `canceled`, `skipped`.

**Step 2 — List jobs to find the failure:**
```bash
.github/skills/gitlab/gitlab pipeline-jobs 12345
```
Look for jobs with `"status": "failed"`. Note the job `id`.

**Step 3 — Read the failed job's log:**
```bash
.github/skills/gitlab/gitlab job-log 67890
```
Output: raw log text. Look for error messages near the end.

### Run a Pipeline

```bash
.github/skills/gitlab/gitlab pipeline-run main
```

Output: pipeline JSON with `id` and `status`. Use `pipeline-get` to poll for completion.

## JSON Field Reference

### mr-create — Required and Optional Fields

| Field | Required | Type | Example |
|-------|----------|------|---------|
| `source_branch` | Yes | string | `"feature/add-auth"` |
| `target_branch` | Yes | string | `"main"` |
| `title` | Yes | string | `"feat: add OAuth login"` |
| `description` | No | string | `"Detailed MR description..."` |
| `assignee_id` | No | number | `42` |
| `reviewer_ids` | No | array | `[42, 43]` |
| `labels` | No | string | `"bug,auth"` (comma-separated) |
| `milestone_id` | No | number | `7` |
| `remove_source_branch` | No | boolean | `true` |
| `squash` | No | boolean | `true` |

### Full mr-create Example

```json
{
  "source_branch": "feature/PROJ-42-oauth-login",
  "target_branch": "main",
  "title": "feat(auth): add OAuth2 PKCE flow",
  "description": "Implements PKCE for public clients.\n\nCloses PROJ-42",
  "labels": "feat,auth",
  "remove_source_branch": true,
  "squash": true
}
```

### mr-update — Partial Field Updates

Same fields as `mr-create` (except `source_branch`). Only include fields you want to change.

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `GITLAB_URL is not set` | Env vars not exported | Export `GITLAB_URL` and `GITLAB_TOKEN` in current shell |
| `GITLAB_TOKEN is not set` | Missing auth token | Generate a PAT in GitLab → Settings → Access Tokens |
| `cannot parse git remote URL` | Not in a git repo or no origin | Set `GITLAB_PROJECT` env var explicitly |
| `HTTP 401` | Bad or expired token | Regenerate PAT; check token has `api` scope |
| `HTTP 403` | Insufficient permissions | Token needs `api` scope; check project membership |
| `HTTP 404` | Wrong project or MR/pipeline ID | Verify `GITLAB_PROJECT`, check MR IID vs ID |
| `expected numeric ID` | Non-numeric argument | MR IIDs, pipeline IDs, and job IDs must be numbers |
| `python3 is required` | python3 not in PATH | Install python3 for your platform |

### MR IID vs ID

GitLab uses two identifiers: **ID** (global, unique across all projects) and **IID** (project-scoped, the `!42` number you see in the UI). This skill uses **IID** for merge requests and **ID** for pipelines and jobs.
