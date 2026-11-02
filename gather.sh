#!/usr/bin/env bash
# Prints the review context for one PR as markdown: ./gather.sh owner/repo 123 tder311
# Exits 3 when the PR isn't open or the reviewer isn't requested on it; FORCE=1 overrides that.
# REST only: cloud sessions block GitHub's GraphQL API, which most `gh pr` commands use.
set -euo pipefail

repo=$1 pr=$2 me=$3
api=repos/$repo
or_none() { local out; out=$(cat); echo "${out:-- none}"; }

pr_json=$(gh api "$api/pulls/$pr")
if [ "${FORCE:-0}" != 1 ]; then
  if [ "$(jq -r .state <<<"$pr_json")" != open ]; then
    echo "skip: $repo#$pr is $(jq -r 'if .merged then "merged" else .state end' <<<"$pr_json")" >&2
    exit 3
  fi
  if ! jq -e --arg me "$me" '[.requested_reviewers[].login] | index($me)' <<<"$pr_json" >/dev/null; then
    echo "skip: $me is not a requested reviewer on $repo#$pr" >&2
    exit 3
  fi
fi

jq -r '
  "# \(.title)\n\nAuthor: \(.user.login). \(.head.ref) -> \(.base.ref). +\(.additions) / -\(.deletions). "
  + "Labels: \([.labels[].name] | join(", ") | if . == "" then "none" else . end).\n\n"
  + "## Description\n\n\(.body // "")"
' <<<"$pr_json"

printf '\n## Commits\n\n'
gh api "$api/pulls/$pr/commits" --paginate --jq '.[] | "- " + (.commit.message | gsub("\n+"; "\n  "))' | or_none

printf '\n## Changed files\n\n'
gh api "$api/pulls/$pr/files" --paginate --jq '.[] | "- `\(.filename)` +\(.additions) -\(.deletions)"' | or_none

printf '\n## CI checks\n\n'
gh api "$api/commits/$(jq -r .head.sha <<<"$pr_json")/check-runs" --paginate \
  --jq '.check_runs[] | "- \(.name): \(.conclusion // .status)"' | or_none

printf '\n## Reviews so far\n\n'
gh api "$api/pulls/$pr/reviews" --paginate \
  --jq '.[] | select(.state != "PENDING") | "- \(.user.login), \(.state) at \(.commit_id[0:7]): \(.body | gsub("\n"; " ") | .[0:1500])"' | or_none

printf '\n## Inline comments so far\n\n'
gh api "$api/pulls/$pr/comments" --paginate \
  --jq '.[] | "- \(.user.login) on `\(.path):\(.line // .original_line)`: \(.body | gsub("\n"; " ") | .[0:800])"' | or_none

printf '\n## Conversation\n\n'
gh api "$api/issues/$pr/comments" --paginate \
  --jq '.[] | "- \(.user.login): \(.body | gsub("\n"; " ") | .[0:1500])"' | or_none

printf '\n## Tom'"'"'s earlier reviews\n\n'
gh api "$api/pulls/$pr/reviews" --paginate \
  --jq "[.[] | select(.user.login == \"$me\" and .state != \"PENDING\")] | \"Tom has submitted \(length) review(s) on this PR.\""
