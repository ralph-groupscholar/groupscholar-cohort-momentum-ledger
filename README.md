# Group Scholar Cohort Momentum Ledger

Track weekly cohort momentum with a lightweight Zig CLI that writes to Postgres. The ledger captures attendance, submissions, and 1:1 sessions so ops can spot momentum shifts quickly.

## Features
- Initialize and seed a Postgres schema for cohort momentum tracking.
- Record weekly momentum entries per cohort.
- List entries with optional cohort filtering.
- Summarize totals and averages for quick reporting.
- Report week-over-week momentum trends with weighted scoring.

## Tech Stack
- Zig 0.15
- PostgreSQL (libpq)

## Getting Started

### 1) Install dependencies
- Zig 0.15+
- libpq (Postgres client libraries)

On macOS with Homebrew:
```
brew install zig libpq
```

### 2) Configure the database
Set a database URL for local development (do not use production credentials on a dev machine):
```
export GS_DATABASE_URL="postgres://USER:PASSWORD@localhost:5432/gs_momentum"
```

### 3) Build
```
zig build
```

### 4) Initialize schema and seed data
```
zig build run -- init-db
zig build run -- seed-db
```

### 5) Record a weekly entry
```
zig build run -- add --cohort "Spring 2026" --week 5 --attendance 42 --submissions 38 --sessions 10 --notes "Resume clinic week"
```

### 6) List entries
```
zig build run -- list --cohort "Spring 2026"
```

### 7) Summarize a cohort
```
zig build run -- summary --cohort "Spring 2026"
```

### 8) View momentum trends
```
zig build run -- trend --cohort "Spring 2026" --weeks 8
```

## Commands
- `init-db`: Apply `sql/schema.sql` to the configured database.
- `seed-db`: Apply `sql/seed.sql` to the configured database.
- `add`: Add a momentum entry.
- `list`: List entries (optionally filtered by cohort).
- `summary`: Aggregate totals and averages (optionally filtered by cohort).
- `trend`: Show recent week-over-week changes and weighted momentum score.

## Notes
- The CLI expects `GS_DATABASE_URL` to be set. Use a local Postgres instance for development.
- Production deployments should inject `GS_DATABASE_URL` via environment variables.

## Testing
Run Zig tests:
```
zig test src/main.zig
```
