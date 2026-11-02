## Repo rubric: modoenergy/data-service (v0, for Tom to edit)

- Re-runs must be idempotent: loading the same window twice must not duplicate rows. Check the write mode and keys of the target table, not just the extract.
- AEMO timestamps are NEM time (UTC+10, no daylight saving, `Australia/Brisbane`), and `SETTLEMENTDATE` marks the end of the interval. Look for off-by-one-interval errors and UTC/local mix-ups at day boundaries.
- DISPATCH tables carry an `INTERVENTION` flag. Check intervention and non-intervention rows aren't mixed or double-counted.
- Airflow changes to `start_date`, `end_date`, `schedule`, `catchup` or concurrency change what the prod scheduler does on deploy. Work out which runs will be created when this merges.
- When Archive and Current disagree for the same interval, which one wins should be a deliberate choice.
