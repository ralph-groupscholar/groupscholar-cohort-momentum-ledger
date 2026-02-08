CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE SCHEMA IF NOT EXISTS groupscholar_cohort_momentum;

CREATE TABLE IF NOT EXISTS groupscholar_cohort_momentum.momentum_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cohort_name TEXT NOT NULL,
  week_index INTEGER NOT NULL,
  attendance_count INTEGER NOT NULL,
  submission_count INTEGER NOT NULL,
  session_count INTEGER NOT NULL,
  notes TEXT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_momentum_entries_cohort_week
  ON groupscholar_cohort_momentum.momentum_entries (cohort_name, week_index);
