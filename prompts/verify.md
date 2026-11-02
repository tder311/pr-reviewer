You are independently checking one claimed bug in {{REPO}}#{{PR}}. You haven't seen anyone's reasoning, only the claim. Decide from the code whether it's real.

The checkout is at the PR's head, and the change is `git diff {{RANGE}}`. Read whatever you need.

Answer:
- CONFIRMED only if you can point to the code that makes the failure scenario happen.
- REFUTED if the code shows it can't happen, or that it's handled.
- UNSURE if it depends on something you can't see from the repo, such as production data or another service. Say what.

Set `pre_existing` to true if the problem also exists on the base branch, so this PR didn't introduce it. Suggest `severity`: Important if it should be fixed before merge, Nit if it's real but minor. Keep `evidence` to the few lines of code and reasoning that settle it.

