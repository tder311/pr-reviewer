Several independent bug hunters reviewed {{REPO}}#{{PR}}. Their candidate findings are below, followed by the PR's context, including everything reviewers have already said.

1. Merge candidates that describe the same underlying problem, even if they cite different lines. Keep the clearest claim and failure scenario and the most specific location, and combine `found_by`.
2. Remove anything that is only about style, naming, formatting, missing tests or cleanup. List it in `dropped` with a reason.
3. Remove anything a reviewer has already raised on the PR. List it in `already_raised`, one line each, naming who raised it.
4. Give each remaining candidate an id: c1, c2, and so on. Keep at most 12, strongest first, and list any extras in `dropped`.

Don't judge whether candidates are true. Verifiers do that next.

## Candidates

