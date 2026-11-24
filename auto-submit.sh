#!/usr/bin/env bash
# Acts on the verdict: submits the review in your name, or holds it as a pending review for you to decide.
# ./auto-submit.sh runs/<owner>__<repo>-<pr>
# Prints "Submitted as <state>: <url>", or "Held for you: <reason>." followed by what post-pending.sh did.
# A high-risk PR is never approved: an Approve verdict is posted as a comment, and it adds "Approval waits for you".
# Before submitting, it resolves your earlier threads that both rechecks say are settled.
# It holds if you submitted a review of your own after the run started (meta.json "started").
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
# If you reviewed the PR yourself while this run was drafting, your review stands and this one waits for you.
started=$(jq -r '.started // empty' "$run/meta.json")
if [ -n "$started" ]; then
  me=$(jq -r '.reviewer // "tder311"' "$run/meta.json")
  yours=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate | jq -s -r --arg me "$me" --arg t "$started" '
    [add // [] | .[] | select(.user.login == $me and .state != "PENDING" and .submitted_at >= $t)]
    | last // empty | "\(.state | ascii_downcase | gsub("_"; " ")) at \(.submitted_at)"')
  [ -z "$yours" ] || hold "you submitted your own review ($yours) while this one was being drafted"
fi
case $decision in
  APPROVE)
    [ "$important" = 0 ] || hold "the verdict is Approve, but there are Important findings"
    open=$(($(jq length "$run/threads.json" 2>/dev/null || echo 0) - $(jq '[.[] | select(.resolve)] | length' "$run/rechecked.json" 2>/dev/null || echo 0)))
    [ "$open" = 0 ] || hold "the verdict is Approve, but $open of your earlier threads still need an answer"
    event=APPROVE
    if [ "$risk" = high ]; then
      event=COMMENT awaiting=1
      # ack-approve.sh looks for the first sentence, so keep it word for word.
      extra=$'\n\nThis is a high-risk change, so I\'ll approve it myself once I\'ve read it. If you\'ve checked the risk and want it approved sooner, reply "high risk acknowledged, please approve".'
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
# Resolve your earlier threads that both checks say are settled, and say so in the review.
resolved=0
for id in $(jq -r '.[] | select(.resolve) | .root_id' "$run/rechecked.json" 2>/dev/null); do
  if gh api -X POST "repos/$repo/pulls/$pr/ccr/comments/$id/resolve" --silent; then
    resolved=$((resolved + 1))
  else
    echo "Couldn't resolve thread $id."
  fi
done
if [ "$resolved" = 1 ]; then
  extra+=$'\n\nResolved one of my earlier threads, which is now addressed.'
elif [ "$resolved" -gt 1 ]; then
  extra+=$'\n\n'"Resolved $resolved of my earlier threads, which are now addressed."
fi
[ "$resolved" = 0 ] || echo "Resolved $resolved earlier thread(s)."

payload=$(jq --arg event "$event" --arg extra "$extra" --arg footer "$footer" \
  '. + {event: $event, body: (.body + $extra + $footer)}' "$run/review.json")

# The claim is a pending review, so release it before submitting.
"$here/claim.sh" "$repo" "$pr" release
gh api -X POST "repos/$repo/pulls/$pr/reviews" --input - --jq '"Submitted as \(.state): \(.html_url)"' <<<"$payload"
[ -z "$awaiting" ] || echo "Approval waits for you: it's high risk."
