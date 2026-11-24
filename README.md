# pr-reviewer

Drafts a review of a pull request when tder311 is asked to review it. The method follows Anthropic's [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/): bug hunters search in parallel, three independent verifiers vote on each candidate, and a writer turns the survivors into a GitHub review.

The output is a private brief, ending in a verdict, and a review. The review covers the Important findings (merging as is would break something) and any questions the author must answer before merge. Nits and pre-existing problems stay in the brief. The cloud task acts on the verdict with `auto-submit.sh`. It submits the review in tder311's name, with a footer saying it was posted automatically. A high-risk PR is never approved automatically: an Approve verdict there is posted as a Comment, and the approval waits for him. It holds the review as a pending review only he can see when a stage failed, the PR changed during the run, he submitted his own review while it was drafting, or there's nothing to post. On a re-review, `threads.sh` lists his unresolved threads from earlier reviews, and two independent checks decide whether each is settled (fixed, or answered). `auto-submit.sh` resolves the settled ones when it submits. After a review is submitted or held, the cloud task replies in the PR's thread in Tom's review group chat on Slack, if one exists, with ✅ approved, 💬 commented, 💬 changes requested, or 👀 reviewing myself for a held review. That uses the Slack connector, limited to reading that chat and sending a reply. For a held review, he replies in the run's session ("comment", "approve, add the nit", "discard") and the agent submits accordingly.

## Run it

```bash
./review.sh owner/repo 123                          # writes runs/<owner>__<repo>-<pr>/brief.md and review.json
./auto-submit.sh runs/<owner>__<repo>-<pr>          # acts on the verdict: submits, or holds as a pending review
./post-pending.sh runs/<owner>__<repo>-<pr>          # saves the draft as a pending review
./submit-pending.sh owner/repo 123 show             # the pending review as it is now on GitHub
./submit-pending.sh owner/repo 123 COMMENT          # submit it (or APPROVE / REQUEST_CHANGES / replace final.json / discard)
```

The cloud task's prompt is `cloud-task-prompt.md`. After editing it, update the task to match.

`review.sh` skips PRs that are closed or where neither tder311 nor a team in `PR_REVIEWER_TEAMS` is a requested reviewer. A team request doesn't count on tder311's own PR. `FORCE=1` overrides that.

Settings, all optional: `HUNT_MODEL` (opus), `VERIFY_MODEL` (sonnet), `WRITE_MODEL` (opus), `LENSES` (correctness data operations code-review), `VOTES_NEEDED` (2), `PARALLEL` (6), `REVIEWER` (tder311), `PR_REVIEWER_TEAMS` (australia), `PR_REVIEWER_CACHE` (~/.cache/pr-reviewer), `CLAIM` (unset). With `CLAIM=1`, as the cloud task runs it, `review.sh` holds a placeholder pending review while it drafts. Every requested reviewer fires its own GitHub event, so this makes later runs for the same PR skip. `auto-submit.sh` or `post-pending.sh` replaces the placeholder.

Runs count against the Claude plan the `claude` CLI is signed in with.

## Layout

- `prompts/`: `hunt.md` plus one file per angle in `lenses/`, `dedupe.md`, `verify.md` plus one file per stance in `stances/`, `recheck.md` plus one file per angle in `recheck/`, `severity.md`, and `write.md`
- `schemas/`: the structured output each stage must return
- `rubrics/`: per-repo checklists added to the hunters' prompts, named `<owner>__<repo>.md`
- `gather.sh`, `claim.sh`, `threads.sh`, `stage.sh`, `review.jq`, `brief.jq`: plumbing for `review.sh`
