#!/usr/bin/env bash
# Acts on the verdict: submits the review in your name, or holds it as a pending review for you to decide.
# ./auto-submit.sh runs/<owner>__<repo>-<pr>
# Prints "Submitted as <state>: <url>", or "Held for you: <reason>." followed by what post-pending.sh did.
# A high-risk PR is never approved: an Approve verdict is posted as a comment, and it adds "Approval waits for you".
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
run=$1
repo=$(jq -r .repo "$run/meta.json")
pr=$(jq -r .pr "$run/meta.json")
sha=$(jq -r .sha "$run/meta.json")
failed=$(jq -r .failed "$run/meta.json")
decision=$(jq -r .verdict.decision "$run/draft.json")
risk=$(jq -r .risk "$run/draft.json")
important=$(jq '[.findings[] | select(.severity == "Important")] | length' "$run/draft.json")
questions=$(jq '.author_questions // [] | length' "$run/draft.json")
footer=$'\n\n---\n_Posted automatically by my PR review agent; I haven\'t read this one myself yet._'
extra=""
awaiting=""

hold() {
  echo "Held for you: $1."
  exec "$here/post-pending.sh" "$run"
}

[ -z "$failed" ] || hold "a stage failed (${failed# }), so the review may be incomplete"
[ "$(gh api "repos/$repo/pulls/$pr" --jq '"\(.state) \(.head.sha)"')" = "open $sha" ] ||
  hold "the PR changed or closed while it was being reviewed"
case $decision in
  APPROVE)
    [ "$important" = 0 ] || hold "the verdict is Approve, but there are Important findings"
    event=APPROVE
    if [ "$risk" = high ]; then
      event=COMMENT awaiting=1
      extra=$'\n\nThis is a high-risk change, so I\'ll approve it myself once I\'ve read it.'
    fi
    ;;
  COMMENT | REQUEST_CHANGES)
    [ "$important" != 0 ] || [ "$questions" != 0 ] ||
      hold "there's nothing to post, with no Important findings and no questions for the author"
    event=$decision
    ;;
  *)
    hold "the draft has no verdict"
    ;;
esac
payload=$(jq --arg event "$event" --arg extra "$extra" --arg footer "$footer" \
  '. + {event: $event, body: (.body + $extra + $footer)}' "$run/review.json")

# The claim is a pending review, so release it before submitting.
"$here/claim.sh" "$repo" "$pr" release
gh api -X POST "repos/$repo/pulls/$pr/reviews" --input - --jq '"Submitted as \(.state): \(.html_url)"' <<<"$payload"
[ -z "$awaiting" ] || echo "Approval waits for you: it's high risk."
