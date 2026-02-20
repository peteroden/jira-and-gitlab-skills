#!/usr/bin/env bash
set -euo pipefail

# Jira REST API v2 client — works with Cloud (API token) and Server/DC (PAT).
# Env: JIRA_BASE_URL (required), JIRA_PAT (Server/DC) or JIRA_USER_EMAIL + JIRA_API_TOKEN (Cloud).

die() { echo "error: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl is required but not installed"
command -v python3 >/dev/null || die "python3 is required but not installed"
[[ -n "${JIRA_BASE_URL:-}" ]] || die "JIRA_BASE_URL is not set"
[[ "$JIRA_BASE_URL" =~ ^https?:// ]] || die "JIRA_BASE_URL must start with https:// (or http:// for local dev)"

API="${JIRA_BASE_URL%/}/rest/api/2"

# Auth: PAT (Bearer) for Server/DC, email+token (Basic) for Cloud
if [[ -n "${JIRA_PAT:-}" ]]; then
  AUTH=(-H "Authorization: Bearer ${JIRA_PAT}")
elif [[ -n "${JIRA_USER_EMAIL:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then
  AUTH=(-u "${JIRA_USER_EMAIL}:${JIRA_API_TOKEN}")
else
  die "Set JIRA_PAT (Server/DC) or JIRA_USER_EMAIL + JIRA_API_TOKEN (Cloud)"
fi

_json() { python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin),indent=2))" 2>/dev/null; }
_json_build() { python3 -c "import sys,json; print(json.dumps(dict(zip(sys.argv[1::2],sys.argv[2::2]))))" "$@"; }
_urlencode() { python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(),safe=''))"; }

_validate_key() {
  [[ "$1" =~ ^[A-Za-z][A-Za-z0-9]+-[0-9]+$ ]] || die "invalid issue key: $1"
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
    print(d.get('errorMessages',d.get('errors',d)),file=sys.stderr)
except: print(sys.stdin.read(),file=sys.stderr)
" <<< "$body" 2>/dev/null || echo "$body" >&2
    die "HTTP $http_code from $method $url"
  fi
  [[ -n "$body" ]] && echo "$body" | _json || true
}

cmd_search() {
  local jql="${1:?usage: jira.sh search <jql> [max_results]}"
  local max="${2:-50}"
  local encoded; encoded=$(echo "$jql" | _urlencode)
  if [[ -n "${JIRA_PAT:-}" ]]; then
    _request GET "${API}/search?jql=${encoded}&maxResults=${max}"
  else
    _request GET "${API}/search/jql?jql=${encoded}&maxResults=${max}&fields=*navigable"
  fi
}

cmd_get() {
  local key="${1:?usage: jira.sh get <issue-key>}"
  _validate_key "$key"
  _request GET "${API}/issue/${key}"
}

cmd_create() {
  local data="${1:-$(cat)}"
  [[ -n "$data" ]] || die "usage: jira.sh create <json> or pipe JSON to stdin"
  _request POST "${API}/issue" -d "$data"
}

cmd_update() {
  local key="${1:?usage: jira.sh update <issue-key> <json>}"
  _validate_key "$key"
  local data="${2:-$(cat)}"
  [[ -n "$data" ]] || die "usage: jira.sh update <issue-key> <json> or pipe JSON to stdin"
  _request PUT "${API}/issue/${key}" -d "$data"
  python3 -c "import json; print(json.dumps({'key':'$key','status':'updated'},indent=2))"
}

cmd_transition() {
  local key="${1:?usage: jira.sh transition <issue-key> <name-or-id>}"
  local target="${2:?usage: jira.sh transition <issue-key> <name-or-id>}"
  _validate_key "$key"
  local tid

  if [[ "$target" =~ ^[0-9]+$ ]]; then
    tid=$target
  else
    tid=$(_request GET "${API}/issue/${key}/transitions" \
      | python3 -c "
import sys,json
data=json.load(sys.stdin)
name=sys.argv[1]
matches=[t['id'] for t in data.get('transitions',[]) if t['name']==name]
print(matches[0] if matches else '',end='')
" "$target")
    [[ -n "$tid" ]] || die "transition '${target}' not found for ${key}"
  fi

  _request POST "${API}/issue/${key}/transitions" -d "{\"transition\":{\"id\":\"${tid}\"}}"
  python3 -c "import json; print(json.dumps({'key':'$key','transitionId':'$tid','status':'transitioned'},indent=2))"
}

cmd_comment() {
  local key="${1:?usage: jira.sh comment <issue-key> <body>}"
  _validate_key "$key"
  local body="${2:-$(cat)}"
  [[ -n "$body" ]] || die "usage: jira.sh comment <issue-key> <body> or pipe body to stdin"
  _request POST "${API}/issue/${key}/comment" -d "$(_json_build body "$body")"
}

cmd_fields() {
  local project="${1:?usage: jira.sh fields <project-key> [issue-type-id]}"
  local type_id="${2:-}"
  if [[ -n "$type_id" ]]; then
    _request GET "${API}/issue/createmeta/${project}/issuetypes/${type_id}"
  else
    _request GET "${API}/issue/createmeta/${project}/issuetypes"
  fi
}

case "${1:-}" in
  search)     shift; cmd_search "$@" ;;
  get)        shift; cmd_get "$@" ;;
  create)     shift; cmd_create "$@" ;;
  update)     shift; cmd_update "$@" ;;
  transition) shift; cmd_transition "$@" ;;
  comment)    shift; cmd_comment "$@" ;;
  fields)     shift; cmd_fields "$@" ;;
  *)          die "usage: jira.sh {search|get|create|update|transition|comment|fields} [args...]" ;;
esac
