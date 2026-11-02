#!/usr/bin/env bash
# Drafts your review of one PR: ./review.sh owner/repo 123
# Bug hunters search in parallel, three verifiers vote on each candidate, and a writer turns the survivors into a draft.
# Writes runs/<owner>__<repo>-<pr>/ with brief.md (private) and review.json (the draft). Posts nothing.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$1 pr=$2
me=${REVIEWER:-tder311}
hunt_model=${HUNT_MODEL:-opus} verify_model=${VERIFY_MODEL:-sonnet} write_model=${WRITE_MODEL:-opus}
lenses=${LENSES:-correctness data operations code-review}
need=${VOTES_NEEDED:-2} par=${PARALLEL:-6}
slug=${repo//\//__}
export WORK=${PR_REVIEWER_CACHE:-$HOME/.cache/pr-reviewer}/$slug
run=$here/runs/$slug-$pr
SECONDS=0
failed=""

rm -rf "$run"
mkdir -p "$run/hunt" "$run/verify"
"$here/gather.sh" "$repo" "$pr" "$me" >"$run/context.md"

[ -d "$WORK/.git" ] || gh repo clone "$repo" "$WORK" -- --filter=blob:none --quiet
# pull/<n>/head survives the head branch being deleted, unlike `gh pr checkout`.
git -C "$WORK" fetch --quiet origin "+refs/heads/*:refs/remotes/origin/*" "+pull/$pr/head:refs/pr-reviewer/$pr"
git -C "$WORK" checkout --quiet --detach "refs/pr-reviewer/$pr"

pr_json=$(gh pr view "$pr" -R "$repo" --json baseRefName,headRefOid,title)
base=origin/$(jq -r .baseRefName <<<"$pr_json")
sha=$(jq -r .headRefOid <<<"$pr_json")
title=$(jq -r .title <<<"$pr_json")
last=$(gh api "repos/$repo/pulls/$pr/reviews" --paginate \
  --jq "[.[] | select(.user.login == \"$me\" and .state != \"PENDING\")] | last | .commit_id // empty")
if [ -n "$last" ] && [ "$last" != "$sha" ] && git -C "$WORK" merge-base --is-ancestor "$last" HEAD 2>/dev/null; then
  range="$last..HEAD" note="Tom last reviewed at ${last:0:7}, so review only what changed since."
else
  range="$base...HEAD" note="Review the whole PR."
fi

# Right-hand-side lines GitHub will accept inline comments on, as path:line.
git -C "$WORK" diff -U3 "$base...HEAD" | awk '
  /^\+\+\+ \/dev\/null/ { f = ""; next }
  /^\+\+\+ b\// { f = substr($0, 7); next }
  /^@@/ { match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
  f != "" && /^[ +]/ { print f ":" n; n++ }
' >"$run/diff-lines.txt"

fill() { sed -e "s|{{REPO}}|$repo|g; s|{{PR}}|$pr|g; s|{{RUN}}|$run|g; s|{{RANGE}}|$range|g; s|{{RANGE_NOTE}}|$note|g"; }
rubric=$here/rubrics/$slug.md
[ -f "$rubric" ] || rubric=/dev/null

# 1. Hunt: one agent per lens, in parallel.
for lens in $lenses; do
  cat "$here/prompts/hunt.md" "$here/prompts/lenses/$lens.md" "$rubric" | fill >"$run/hunt/$lens.md"
  extra=""
  [ "$lens" != code-review ] || extra="Skill,Agent"
  EXTRA_TOOLS=$extra "$here/stage.sh" "$hunt_model" "$here/schemas/candidates.json" "$run/hunt/$lens.md" "$run/hunt/$lens.json" &
done
wait

: >"$run/candidates.jsonl"
for lens in $lenses; do
  if [ -s "$run/hunt/$lens.json" ]; then
    jq -c --arg lens "$lens" '.candidates | map(. + {found_by: [$lens]})' "$run/hunt/$lens.json" >>"$run/candidates.jsonl"
  else
    failed="$failed hunt:$lens"
  fi
done
jq -s 'add // []' "$run/candidates.jsonl" >"$run/candidates.json"

# 2. Merge duplicates and drop what's already been said. Without this step, verify every raw candidate.
if [ "$(jq length "$run/candidates.json")" -gt 0 ]; then
  {
    fill <"$here/prompts/dedupe.md"
    jq . "$run/candidates.json"
    printf '\n## PR context\n\n'
    cat "$run/context.md"
  } >"$run/dedupe.md"
  "$here/stage.sh" sonnet "$here/schemas/deduped.json" "$run/dedupe.md" "$run/deduped.json" || failed="$failed dedupe"
fi
[ -s "$run/deduped.json" ] || jq '{candidates: (to_entries | map(.value + {id: "c\(.key + 1)"})), already_raised: [], dropped: []}' \
  "$run/candidates.json" >"$run/deduped.json"

# 3. Verify: three fresh verifiers per candidate, each with a different stance and only the claim to go on.
jq -c '.candidates[]' "$run/deduped.json" | while read -r c; do
  id=$(jq -r .id <<<"$c")
  for stance in skeptic tracer context; do
    {
      fill <"$here/prompts/verify.md"
      cat "$here/prompts/stances/$stance.md"
      printf '\n## The claim\n\n'
      jq '{path, line, claim, failure_scenario}' <<<"$c"
    } >"$run/verify/$id-$stance.md"
  done
done
i=0
for p in "$run"/verify/*.md; do
  [ -e "$p" ] || break
  "$here/stage.sh" "$verify_model" "$here/schemas/verdict.json" "$p" "${p%.md}.json" &
  i=$((i + 1))
  [ $((i % par)) -ne 0 ] || wait
done
wait

: >"$run/verdicts.jsonl"
for f in "$run"/verify/*.json; do
  [ -e "$f" ] || break
  b=$(basename "$f" .json)
  jq -c --arg id "${b%-*}" --arg stance "${b##*-}" '. + {id: $id, stance: $stance}' "$f" >>"$run/verdicts.jsonl"
done
missing=$((i - $(wc -l <"$run/verdicts.jsonl")))
[ "$missing" -eq 0 ] || failed="$failed verify:$missing-of-$i"
jq --slurpfile v "$run/verdicts.jsonl" --argjson need "$need" '
  .candidates | map(
    . as $c | ($v | map(select(.id == $c.id))) as $votes
    | $c + {votes: $votes, confirmed: ($votes | map(select(.verdict == "CONFIRMED")) | length)}
    | . + {kept: (.confirmed >= $need)}
  )' "$run/deduped.json" >"$run/votes.json"

# 4. Write: turn the survivors into Tom's draft and brief.
{
  fill <"$here/prompts/write.md"
  printf '\n## Survivors\n\n'
  jq '[.[] | select(.kept) | del(.votes[].id)]' "$run/votes.json"
  printf '\n## Not confirmed, but some verifiers were unsure\n\n'
  jq '[.[] | select((.kept | not) and any(.votes[]; .verdict == "UNSURE"))
       | {id, path, line, claim, unsure: [.votes[] | select(.verdict == "UNSURE") | .evidence]}]' "$run/votes.json"
  printf '\n## Already raised\n\n'
  jq .already_raised "$run/deduped.json"
} >"$run/write.md"
"$here/stage.sh" "$write_model" "$here/schemas/draft.json" "$run/write.md" "$run/draft.json"

jq -n --arg repo "$repo" --argjson pr "$pr" '{repo: $repo, pr: $pr}' >"$run/meta.json"
jq --arg sha "$sha" --rawfile lines "$run/diff-lines.txt" -f "$here/review.jq" "$run/draft.json" >"$run/review.json"
cost=$(find "$run" -name '*.raw' -exec jq '.total_cost_usd // 0' {} + | jq -s 'add * 100 | round / 100')
jq -r --arg repo "$repo" --arg pr "$pr" --arg title "$title" --arg range "$range" \
  --arg mins "$((SECONDS / 60))" --arg cost "$cost" --arg need "$need" --arg failed "$failed" \
  --slurpfile votes "$run/votes.json" --slurpfile filtered "$run/deduped.json" \
  -f "$here/brief.jq" "$run/draft.json" >"$run/brief.md"

echo "$run/brief.md"
