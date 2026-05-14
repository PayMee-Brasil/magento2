#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "Usage: SLACK_WEBHOOK_URL=... $0 <repository> <pr-title> <pr-url> <source-branch> <target-branch>" >&2
  exit 2
fi

if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "SLACK_WEBHOOK_URL is required but was not provided." >&2
  exit 1
fi

repository="$1"
pr_title="$2"
pr_url="$3"
source_branch="$4"
target_branch="$5"

payload="$(jq -n \
  --arg repository "${repository}" \
  --arg pr_title "${pr_title}" \
  --arg pr_url "${pr_url}" \
  --arg source_branch "${source_branch}" \
  --arg target_branch "${target_branch}" \
  '{
    text: "PR de rollout criada",
    blocks: [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: ":github: *PR de rollout criada*\n*Repositório:* \($repository)\n*PR:* <\($pr_url)|\($pr_title)>\n*Branch:* `\($source_branch)` → `\($target_branch)`"
        }
      }
    ]
  }')"

curl --fail --silent --show-error \
  --request POST \
  --header 'Content-type: application/json' \
  --data "${payload}" \
  "${SLACK_WEBHOOK_URL}"
