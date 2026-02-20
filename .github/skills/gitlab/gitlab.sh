#!/usr/bin/env bash
set -euo pipefail

# GitLab REST API v4 client — works with GitLab.com and self-managed instances.
# Env: GITLAB_URL, GITLAB_TOKEN (required). GITLAB_PROJECT (optional, auto-detected from git remote).

die() { echo "error: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required but not installed"
command -v python3 >/dev/null || die "python3 is required but not installed"
[[ -n "${GITLAB_URL:-}" ]] || die "GITLAB_URL is not set"
[[ "$GITLAB_URL" =~ ^https?:// ]] || die "GITLAB_URL must start with https:// (or http:// for local dev)"
[[ -n "${GITLAB_TOKEN:-}" ]] || die "GITLAB_TOKEN is not set"

API="${GITLAB_URL%/}/api/v4"
AUTH=(-H "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

_json() { python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin),indent=2))" 2>/dev/null; }
_json_build() { python3 -c "import sys,json; print(json.dumps(dict(zip(sys.argv[1::2],sys.argv[2::2]))))" "$@"; }

_validate_id() {
  [[ "$1" =~ ^[0-9]+$ ]] || die "expected numeric ID, got: $1"
}

_project() {
  if [[ -n "${GITLAB_PROJECT:-}" ]]; then
    echo "$GITLAB_PROJECT"
    return
  fi
  local url
  url=$(git remote get-url origin 2>/dev/null) || die "GITLAB_PROJECT not set and no git remote found"
  local path
  # Handle SSH (git@gitlab.com:group/project.git) and HTTPS (https://gitlab.com/group/project.git)
  if [[ "$url" =~ ^git@ ]]; then
    path="${url#*:}"
  elif [[ "$url" =~ ^https?:// ]]; then
    path="${url#*://*/}"
  else
    die "cannot parse git remote URL: $url"
  fi
  path="${path%.git}"
  [[ -n "$path" ]] || die "cannot extract project path from remote: $url"
  # URL-encode slashes for GitLab API
  echo "${path//\//%2F}"
}

_request() {
  local method=$1 url=$2; shift 2
  local response http_code body
  response=$(curl -s -w '\n%{http_code}' -X "$method" "${AUTH[@]}" \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    "$url" "$@")
  http_code=$(tail -1 <<< "$response")
  body=$(sed '$d' <<< "$response")
  if [[ $http_code -ge 400 ]]; then
    python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('message',d.get('error',d)),file=sys.stderr)
except: print(sys.stdin.read(),file=sys.stderr)
" <<< "$body" 2>/dev/null || echo "$body" >&2
    die "HTTP $http_code from $method $url"
  fi
  [[ -n "$body" ]] && echo "$body" | _json || true
}

# --- Merge Request commands ---

cmd_mr_list() {
  local state="${1:-all}" max="${2:-20}"
  _request GET "${API}/projects/$(_project)/merge_requests?state=${state}&per_page=${max}&order_by=created_at&sort=desc"
}

cmd_mr_get() {
  local iid="${1:?usage: gitlab.sh mr-get <mr-iid>}"
  _validate_id "$iid"
  _request GET "${API}/projects/$(_project)/merge_requests/${iid}"
}

cmd_mr_create() {
  local data="${1:-$(cat)}"
  [[ -n "$data" ]] || die "usage: gitlab.sh mr-create <json> or pipe JSON to stdin"
  _request POST "${API}/projects/$(_project)/merge_requests" -d "$data"
}

cmd_mr_update() {
  local iid="${1:?usage: gitlab.sh mr-update <mr-iid> <json>}"
  _validate_id "$iid"
  local data="${2:-$(cat)}"
  [[ -n "$data" ]] || die "usage: gitlab.sh mr-update <mr-iid> <json> or pipe JSON to stdin"
  _request PUT "${API}/projects/$(_project)/merge_requests/${iid}" -d "$data"
}

cmd_mr_comment() {
  local iid="${1:?usage: gitlab.sh mr-comment <mr-iid> <body>}"
  _validate_id "$iid"
  local body="${2:-$(cat)}"
  [[ -n "$body" ]] || die "usage: gitlab.sh mr-comment <mr-iid> <body> or pipe body to stdin"
  _request POST "${API}/projects/$(_project)/merge_requests/${iid}/notes" \
    -d "$(_json_build body "$body")"
}

# --- Pipeline & Job commands ---

cmd_pipeline_get() {
  local pid="${1:?usage: gitlab.sh pipeline-get <pipeline-id>}"
  _validate_id "$pid"
  _request GET "${API}/projects/$(_project)/pipelines/${pid}"
}

cmd_pipeline_run() {
  local ref="${1:?usage: gitlab.sh pipeline-run <branch-or-tag>}"
  _request POST "${API}/projects/$(_project)/pipelines" \
    -d "$(_json_build ref "$ref")"
}

cmd_pipeline_jobs() {
  local pid="${1:?usage: gitlab.sh pipeline-jobs <pipeline-id>}"
  _validate_id "$pid"
  _request GET "${API}/projects/$(_project)/pipelines/${pid}/jobs"
}

cmd_job_log() {
  local jid="${1:?usage: gitlab.sh job-log <job-id>}"
  _validate_id "$jid"
  # Job trace returns plain text, not JSON
  local response http_code body
  response=$(curl -s -w '\n%{http_code}' -X GET "${AUTH[@]}" \
    "${API}/projects/$(_project)/jobs/${jid}/trace")
  http_code=$(tail -1 <<< "$response")
  body=$(sed '$d' <<< "$response")
  if [[ $http_code -ge 400 ]]; then
    echo "$body" >&2
    die "HTTP $http_code fetching job log"
  fi
  echo "$body"
}

# --- Dispatch ---

case "${1:-}" in
  mr-list)        shift; cmd_mr_list "$@" ;;
  mr-get)         shift; cmd_mr_get "$@" ;;
  mr-create)      shift; cmd_mr_create "$@" ;;
  mr-update)      shift; cmd_mr_update "$@" ;;
  mr-comment)     shift; cmd_mr_comment "$@" ;;
  pipeline-get)   shift; cmd_pipeline_get "$@" ;;
  pipeline-run)   shift; cmd_pipeline_run "$@" ;;
  pipeline-jobs)  shift; cmd_pipeline_jobs "$@" ;;
  job-log)        shift; cmd_job_log "$@" ;;
  *)              die "usage: gitlab.sh {mr-list|mr-get|mr-create|mr-update|mr-comment|pipeline-get|pipeline-run|pipeline-jobs|job-log} [args...]" ;;
esac
