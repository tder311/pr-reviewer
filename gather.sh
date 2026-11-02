#!/usr/bin/env bash
# Prints the review context for one PR as markdown: ./gather.sh owner/repo 123 tder311
# Exits 3 when the PR isn't open or the reviewer isn't requested on it; FORCE=1 overrides that.
set -euo pipefail

repo=$1 pr=$2 me=$3
api=repos/$repo
or_none() { local out; out=$(cat); echo "${out:-- none}"; }

pr_json=$(gh pr view "$pr" -R "$repo" --json state,title,author,baseRefName,headRefName,additions,deletions,labels,body,commits,files,reviewRequests)
if [ "${FORCE:-0}" != 1 ]; then
  if [ "$(jq -r .state <<<"$pr_json")" != OPEN ]; then
    echo "skip: $repo#$pr is $(jq -r '.state | ascii_downcase' <<<"$pr_json")" >&2
    exit 3
  fi
  if ! jq -e --arg me "$me" '[.reviewRequests[].login] | index($me)' <<<"$pr_json" >/dev/null; then
    echo "skip: $me is not a requested reviewer on $repo#$pr" >&2
    exit 3
  fi
fi

jq -r '
  "# \(.title)\n\nAuthor: \(.author.login). \(.headRefName) -> \(.baseRefName). +\(.additions) / -\(.deletions). "
  + "Labels: \([.labels[].name] | join(", ") | if . == "" then "none" else . end).\n\n"
  + "## Description\n\n\(.body)\n\n"
  + "## Commits\n\n\(.commits | map("- \(.messageHeadline)" + (if .messageBody != "" then "\n  \(.messageBody | gsub("\n"; "\n  "))" else "" end)) | join("\n"))\n\n"
  + "## Changed files\n\n\(.files | map("- `\(.path)` +\(.additions) -\(.deletions)") | join("\n"))"
' <<<"$pr_json"

printf '\n## CI checks\n\n'
gh pr checks "$pr" -R "$repo" --json name,state --jq '.[] | "- \(.name): \(.state)"' 2>/dev/null | or_none

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
