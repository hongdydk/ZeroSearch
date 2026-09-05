#!/usr/bin/env bash
# Post a failure event to Cursor Automations webhook.
# Skips gracefully when CURSOR_AUTOMATION_WEBHOOK_URL / KEY are unset.
set -euo pipefail

EVENT="${1:-unknown}"
MESSAGE="${2:-}"
JOB="${3:-${GITHUB_JOB:-unknown}}"

URL="${CURSOR_AUTOMATION_WEBHOOK_URL:-}"
KEY="${CURSOR_AUTOMATION_WEBHOOK_KEY:-}"

if [[ -z "$URL" || -z "$KEY" ]]; then
  echo "skip Cursor Automations notify — CURSOR_AUTOMATION_WEBHOOK_URL/KEY not set"
  exit 0
fi

REPO="${GITHUB_REPOSITORY:-unknown}"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0}"
if [[ -z "$MESSAGE" ]]; then
  MESSAGE="GitHub Actions failure: event=${EVENT} job=${JOB}"
fi

payload="$(
  EVENT="$EVENT" REPO="$REPO" RUN_URL="$RUN_URL" JOB="$JOB" MESSAGE="$MESSAGE" python3 -c '
import json, os
print(json.dumps({
  "source": "github-actions",
  "event": os.environ["EVENT"],
  "repo": os.environ["REPO"],
  "run_url": os.environ["RUN_URL"],
  "job": os.environ["JOB"],
  "message": os.environ["MESSAGE"],
}, ensure_ascii=False))
'
)"

curl -sfS -X POST "$URL" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d "$payload"
echo
echo "Cursor Automations notify sent: event=$EVENT job=$JOB"
