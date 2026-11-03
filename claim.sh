#!/usr/bin/env bash
# Holds a placeholder pending review while a run drafts yours, so only one run drafts per PR.
# GitHub fires one review_requested event per requested reviewer, but allows only one pending review per person per PR.
#   ./claim.sh owner/repo 123 take <head sha>    exits 3 if you already have a pending review or another run holds the claim
#   ./claim.sh owner/repo 123 release            deletes the placeholder, if it's there
set -euo pipefail

repo=$1 pr=$2 action=$3
api=repos/$repo/pulls/$pr
marker="pr-reviewer is drafting this review"

# A claim older than 30 minutes belongs to a run that died before releasing it.
pending=$(gh api "$api/reviews" --paginate | jq -c -s --arg m "$marker" '
  add // [] | map(select(.state == "PENDING"))[0] // empty
  | (.body | startswith($m)) as $claim
  | {id, claim: $claim, stale: ($claim and ((.body | capture("since (?<t>[0-9:TZ-]+)").t | fromdateiso8601) < now - 1800))}')
field() { jq -r ".$1" <<<"$pending"; }

case $action in
  take)
    if [ -n "$pending" ]; then
      if [ "$(field stale)" = true ]; then
        gh api -X DELETE "$api/reviews/$(field id)" --silent
      elif [ "$(field claim)" = true ]; then
        echo "skip: another run is already drafting your review of $repo#$pr" >&2
        exit 3
      else
        echo "skip: you already have a pending review on $repo#$pr" >&2
        exit 3
      fi
    fi
    body="$marker, since $(date -u +%Y-%m-%dT%H:%M:%SZ). If it's still here after 30 minutes, the run failed: discard it."
    if ! out=$(gh api -X POST "$api/reviews" -f commit_id="$4" -f body="$body" 2>&1); then
      grep -q 'one pending review' <<<"$out" || { echo "$out" >&2; exit 1; }
      echo "skip: another run is already drafting your review of $repo#$pr" >&2
      exit 3
    fi
    ;;
  release)
    [ -z "$pending" ] || [ "$(field claim)" != true ] || gh api -X DELETE "$api/reviews/$(field id)" --silent
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 2
    ;;
esac
