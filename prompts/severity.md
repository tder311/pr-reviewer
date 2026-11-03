
## Severity

Only Important findings are posted on the PR. Everything else stays in Tom's private brief, so set a high bar.

- **Important**: merging as is would break something. The code never runs or fails every time. It writes wrong numbers, or loses or duplicates data, without failing. Or it breaks a caller.
- **Nit**: real but minor. This includes fixes that only change a comment, docstring or log message. It includes occasional failures that show up as a failed task and are fixed by rerunning. And it includes problems that only appear if someone later changes a default or a flag.
