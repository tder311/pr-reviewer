#!/usr/bin/env bash
# Prints your unresolved review threads on a PR as JSON: ./threads.sh owner/repo 123 tder311
#   [{root_id, path, line, outdated, comments: [{user, body}]}], oldest first.
# GitHub only exposes thread resolution through GraphQL, which cloud sessions block, so this uses the cloud proxy's
# REST endpoint for threads and falls back to GraphQL elsewhere.
set -euo pipefail

repo=$1 pr=$2 me=$3
api=repos/$repo/pulls/$pr

if ! threads=$(gh api "$api/ccr/review_threads" 2>/dev/null); then
  threads=$(gh api graphql -F owner="${repo%/*}" -F name="${repo#*/}" -F pr="$pr" -f query='
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $pr) { reviewThreads(first: 100) { nodes {
        isResolved isOutdated path line comments(first: 100) { nodes { databaseId } }
      } } } }
    }' --jq '[.data.repository.pullRequest.reviewThreads.nodes[]
      | {resolved: .isResolved, outdated: .isOutdated, path, line, comment_ids: [.comments.nodes[].databaseId]}]')
fi

gh api "$api/comments" --paginate | jq -s --argjson threads "$threads" --arg me "$me" '
  (add // [] | INDEX(.id | tostring)) as $by_id
  | [$threads[] | select(.resolved | not)
     | {path, line, outdated, comments: [.comment_ids[] | $by_id[tostring] | select(.)]}
     | select(.comments[0].user.login == $me)
     | {root_id: .comments[0].id, path, line, outdated, comments: (.comments | map({user: .user.login, body}))}]
  | sort_by(.root_id)'
