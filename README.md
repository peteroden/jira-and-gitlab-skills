# Jira and GitLab Skills for GitHub Copilot

Copilot coding agent skills for managing Jira issues and GitLab merge requests / CI pipelines directly from your editor.

## Skills

### Jira

Create tickets, update stories, search with JQL, transition issues between statuses, add comments, and look up issue details. Works with both Jira Cloud and Jira Server/Data Center.

**Required environment variables:**

| Variable | When required | Purpose |
|----------|--------------|---------|
| `JIRA_BASE_URL` | Always | Jira instance URL |
| `JIRA_USER_EMAIL` | Cloud | Account email for basic auth |
| `JIRA_API_TOKEN` | Cloud | API token paired with email |
| `JIRA_PAT` | Server/DC | Personal access token (bearer auth) |

### GitLab

Create and update merge requests, add MR comments, check pipeline status, read job logs, trigger pipeline runs, and debug CI failures. Works with both GitLab.com and self-managed instances.

**Required environment variables:**

| Variable | Required | Purpose |
|----------|----------|---------|
| `GITLAB_URL` | Always | Instance URL |
| `GITLAB_TOKEN` | Always | Personal access token with `api` scope |
| `GITLAB_PROJECT` | Optional | Project ID or URL-encoded path (auto-detected from git remote if unset) |

## Installation

Copy the `.github/skills/` directory into your repository:

```bash
cp -r .github/skills/jira <your-repo>/.github/skills/
cp -r .github/skills/gitlab <your-repo>/.github/skills/
```

Both skills require `curl` and `python3` at runtime.

## License

[MIT](LICENSE)
