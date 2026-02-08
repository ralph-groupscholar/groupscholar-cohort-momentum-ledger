# Ralph Progress Log

## 2026-02-08
- Initialized groupscholar-cohort-momentum-ledger Zig CLI.
- Added Postgres schema/seed SQL and libpq-backed commands (init-db, seed-db, add, list, summary).
- Documented setup, usage, and testing.
- Added CSV export command with safe escaping and documentation updates.
- Added a trend report command with weighted momentum scoring and week-over-week deltas.
- Added cohort alerts for low momentum and sharp drops; reseeded production schema data.
