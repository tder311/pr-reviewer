#!/usr/bin/env bash
# Acts on your pending review of a PR. Run it only after you've said what to do with the review.
#   ./submit-pending.sh owner/repo 123 show                     print the pending review as it is now on GitHub
#   ./submit-pending.sh owner/repo 123 COMMENT ["summary"]      submit it as is (or APPROVE / REQUEST_CHANGES)
#   ./submit-pending.sh owner/repo 123 replace final.json       submit final.json in its place (for edits)
#   ./submit-pending.sh owner/repo 123 discard                  delete it unsent
# final.json is a review payload: {event, body, comments: [...]}. Each comment is {path, line, side: "RIGHT", body},
# or {path, position, body} to keep a pending comment where it is (`show` prints each one's position).
# With no pending review (nothing was found), COMMENT/APPROVE/REQUEST_CHANGES submit a review with just the summary.
set -euo pipefail

repo=$1 pr=$2 action=$3
api=repos/$repo/pulls/$pr
events='["COMMENT", "APPROVE", "REQUEST_CHANGES"]'
is_event() { jq -en --arg e "$1" "$events | index(\$e)" >/dev/null; }
# GitHub returns pending comments with a diff position but no line number, so read the line off the end of the hunk.
hunk_line='def hunk_line: (.diff_hunk | split("\n")) as $l
  | ($l[0] | capture("\\+(?<s>[0-9]+)").s | tonumber) + ($l[1:] | map(select(test("^[-\\\\]") | not)) | length) - 1;'

id=$(gh api "$api/reviews" --paginate --jq '.[] | select(.state == "PENDING") | .id')
if [ -z "$id" ]; then
  is_event "$action" || { echo "No pending review of yours on $repo#$pr." >&2; exit 1; }
  [ -n "${4:-}" ] || [ "$action" = APPROVE ] || { echo "$action without a pending review needs a summary." >&2; exit 2; }
  gh api -X POST "$api/reviews" -f "event=$action" -f "body=${4:-}" --jq '"Submitted as \(.state): \(.html_url)"'
  exit
fi

case $action in
  show)
    gh api "$api/reviews/$id" --jq '"Summary: \(.body)\n"'
    gh api "$api/reviews/$id/comments" --paginate | jq -r -s "$hunk_line"'
      add // [] | .[] | "- `\(.path):\(hunk_line)` (position \(.position)): \(.body)"'
    ;;
  COMMENT | APPROVE | REQUEST_CHANGES)
    body=${4:-$(gh api "$api/reviews/$id" --jq .body)}
    gh api -X POST "$api/reviews/$id/events" -f "event=$action" -f "body=$body" \
      --jq '"Submitted as \(.state): \(.html_url)"'
    ;;
  replace)
    is_event "$(jq -r .event "$4")" || { echo "$4 needs event COMMENT, APPROVE or REQUEST_CHANGES." >&2; exit 2; }
    # GitHub allows one pending review per person, so keep a copy to restore if the new one is rejected.
    # Multi-line comments come back as their last line only.
    backup=$(mktemp)
    gh api "$api/reviews/$id/comments" --paginate | jq -s --arg body "$(gh api "$api/reviews/$id" --jq .body)" '
      {body: $body, comments: (add // [] | map({path, position, body}))}' >"$backup"
    gh api -X DELETE "$api/reviews/$id" --silent
    if ! gh api -X POST "$api/reviews" --input "$4" --jq '"Submitted as \(.state): \(.html_url)"'; then
      echo "GitHub rejected $4; restoring your pending review." >&2
      gh api -X POST "$api/reviews" --input "$backup" --silent
      exit 1
    fi
    ;;
  discard)
    gh api -X DELETE "$api/reviews/$id" --silent
    echo "Discarded your pending review on $repo#$pr."
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 2
    ;;
esac
