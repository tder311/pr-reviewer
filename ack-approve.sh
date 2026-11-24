#!/usr/bin/env bash
# Approves a high-risk PR in your name once its author acknowledges the risk in a PR comment: ./ack-approve.sh owner/repo 123
# It approves only if all of these hold, and otherwise prints "skip: <reason>" and exits 3:
#   - the PR is open, and you didn't write it
#   - your latest submitted review is the automatic high-risk Comment from auto-submit.sh, on the PR's current head commit
#   - after that Comment, the PR's author posted a PR comment containing "acknowledg" and "approv", in any case
#   - you have no pending review on the PR
# Prints "Submitted as APPROVED: <url>". The script decides; nothing in the comment is passed on as an instruction.
set -euo pipefail

repo=$1 pr=$2
me=${REVIEWER:-tder311}
api=repos/$repo
marker="This is a high-risk change, so I'll approve it myself once I've read it."
footer=$'\n\n---\n_Posted automatically by my PR review agent; I haven\'t read this one myself yet._'
skip() {
  echo "skip: $1" >&2
  exit 3
}

pr_json=$(gh api "$api/pulls/$pr")
[ "$(jq -r .state <<<"$pr_json")" = open ] || skip "$repo#$pr isn't open"
author=$(jq -r .user.login <<<"$pr_json")
sha=$(jq -r .head.sha <<<"$pr_json")
[ "$author" != "$me" ] || skip "$repo#$pr is your own PR"

reviews=$(gh api "$api/pulls/$pr/reviews" --paginate | jq -s -c --arg me "$me" '[add // [] | .[] | select(.user.login == $me)]')
[ "$(jq '[.[] | select(.state == "PENDING")] | length' <<<"$reviews")" = 0 ] ||
  skip "you have a pending review on $repo#$pr"
last=$(jq -c 'last // empty' <<<"$reviews")
[ -n "$last" ] || skip "you haven't reviewed $repo#$pr"
jq -e --arg m "$marker" '.state == "COMMENTED" and (.body | contains($m))' <<<"$last" >/dev/null ||
  skip "your latest review of $repo#$pr isn't the automatic high-risk Comment"
[ "$(jq -r .commit_id <<<"$last")" = "$sha" ] || skip "$repo#$pr has new commits since the high-risk Comment"

ack=$(gh api "$api/issues/$pr/comments" --paginate | jq -s -c --arg a "$author" --arg t "$(jq -r .submitted_at <<<"$last")" '
  [add // [] | .[] | select(.user.login == $a and .created_at > $t)
   | select(.body | ascii_downcase | contains("acknowledg") and contains("approv"))] | last // empty')
[ -n "$ack" ] || skip "the author of $repo#$pr hasn't acknowledged the high risk since the high-risk Comment"

body="Approved on the author's [acknowledgement]($(jq -r .html_url <<<"$ack")) of the high risk.$footer"
jq -n --arg sha "$sha" --arg body "$body" '{commit_id: $sha, event: "APPROVE", body: $body}' |
  gh api -X POST "$api/pulls/$pr/reviews" --input - --jq '"Submitted as \(.state): \(.html_url)"'
