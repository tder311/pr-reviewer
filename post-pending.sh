#!/usr/bin/env bash
# Saves a drafted review on GitHub as PENDING: only you can see it until you edit and submit it.
# ./post-pending.sh runs/<owner>__<repo>-<pr>
set -euo pipefail

run=$1
repo=$(jq -r .repo "$run/meta.json")
pr=$(jq -r .pr "$run/meta.json")

if [ "$(jq '[.findings[] | select(.severity == "Important")] | length' "$run/draft.json")" = 0 ]; then
  echo "Nothing to fix before merge, so no pending review was saved on $repo#$pr."
  exit 0
fi

# GitHub allows one pending review per person per PR.
if [ "$(gh api "repos/$repo/pulls/$pr/reviews" --paginate --jq '[.[] | select(.state == "PENDING")] | length')" != 0 ]; then
  echo "You already have a pending review on $repo#$pr. Submit or discard it first." >&2
  exit 1
fi

gh api -X POST "repos/$repo/pulls/$pr/reviews" --input "$run/review.json" \
  --jq '"Pending review saved: \(.html_url)"'
