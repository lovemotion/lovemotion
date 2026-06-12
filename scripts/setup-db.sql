-- LoveMotion database schema
-- Run as: psql -U lovemotion -d lovemotion -f setup-db.sql

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Growth Companion snapshots
CREATE TABLE IF NOT EXISTS companions (
  companion_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  heyu_user_ref         TEXT NOT NULL UNIQUE,
  embedding             vector(1536),
  growth_level          INTEGER NOT NULL DEFAULT 1 CHECK (growth_level BETWEEN 1 AND 7),
  proof_of_work_score   FLOAT NOT NULL DEFAULT 0.0 CHECK (proof_of_work_score BETWEEN 0.0 AND 1.0),
  contribution_score    FLOAT NOT NULL DEFAULT 0.0 CHECK (contribution_score BETWEEN 0.0 AND 1.0),
  attachment_style      TEXT CHECK (attachment_style IN ('secure','anxious','avoidant','disorganized')),
  growth_velocity       FLOAT DEFAULT 0.0,
  trajectory_direction  vector(32),
  geographic_region     TEXT,
  lifestyle_axes        JSONB DEFAULT '{}',
  last_circle_signals   JSONB DEFAULT '{}',
  eligible_for_matching BOOLEAN DEFAULT FALSE,
  match_cooldown_until  TIMESTAMPTZ,
  snapshot_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ANN index for fast candidate generation
CREATE INDEX IF NOT EXISTS companions_embedding_idx
  ON companions USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

CREATE INDEX IF NOT EXISTS companions_eligible_idx
  ON companions (eligible_for_matching, match_cooldown_until)
  WHERE eligible_for_matching = TRUE;

-- Match results
CREATE TABLE IF NOT EXISTS match_results (
  match_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  companion_id_a        UUID NOT NULL REFERENCES companions(companion_id) ON DELETE CASCADE,
  companion_id_b        UUID NOT NULL REFERENCES companions(companion_id) ON DELETE CASCADE,
  score                 FLOAT NOT NULL CHECK (score BETWEEN 0.0 AND 1.0),
  explanation           JSONB NOT NULL DEFAULT '[]',
  ready                 BOOLEAN DEFAULT FALSE,
  pipeline_run_id       UUID NOT NULL,
  simulated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  consumed_by_heyu_at   TIMESTAMPTZ,
  CONSTRAINT canonical_pair CHECK (companion_id_a < companion_id_b),
  UNIQUE (companion_id_a, companion_id_b, pipeline_run_id)
);

CREATE INDEX IF NOT EXISTS match_results_unconsumed_idx
  ON match_results (simulated_at)
  WHERE consumed_by_heyu_at IS NULL AND ready = TRUE;

-- Pipeline run audit log
CREATE TABLE IF NOT EXISTS simulation_log (
  run_id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  started_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at          TIMESTAMPTZ,
  companions_evaluated  INTEGER DEFAULT 0,
  pairs_simulated       INTEGER DEFAULT 0,
  matches_produced      INTEGER DEFAULT 0,
  config_snapshot       JSONB DEFAULT '{}'
);
