# pr-reviewer

Drafts a review of a pull request when tder311 is asked to review it. The method follows Anthropic's [How the Claude Code team does code review](https://claude.dev/blog/solving-code-review-at-anthropic/): bug hunters search in parallel, three independent verifiers vote on each candidate, and a writer turns the survivors into a GitHub review.

It never submits anything. The output is a private brief and a draft that can be saved as a pending review, which only its author can see until they edit and submit it.

## Run it

```bash
./review.sh owner/repo 123                  # writes runs/<owner>__<repo>-<pr>/brief.md and review.json
./post-pending.sh runs/<owner>__<repo>-<pr>  # saves the draft as a pending review
```

`review.sh` skips PRs that are closed or where tder311 isn't a requested reviewer; `FORCE=1` overrides that.

Settings, all optional: `HUNT_MODEL` (opus), `VERIFY_MODEL` (sonnet), `WRITE_MODEL` (opus), `LENSES` (correctness data operations code-review), `VOTES_NEEDED` (2), `PARALLEL` (6), `REVIEWER` (tder311), `PR_REVIEWER_CACHE` (~/.cache/pr-reviewer).

Runs count against the Claude plan the `claude` CLI is signed in with.

## Layout

- `prompts/`: `hunt.md` plus one file per angle in `lenses/`, `dedupe.md`, `verify.md` plus one file per stance in `stances/`, and `write.md`
- `schemas/`: the structured output each stage must return
- `rubrics/`: per-repo checklists added to the hunters' prompts, named `<owner>__<repo>.md`
- `gather.sh`, `stage.sh`, `review.jq`, `brief.jq`: plumbing for `review.sh`
