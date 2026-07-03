-- LoveMotion v0 schema
-- Design rationale: Handoff.md "Postgres schema" section.
--
-- Iron rules encoded here:
--   * axis_values is APPEND-ONLY. PK (twin_id, axis_id, observed_at); never
--     UPDATE. Runs read latest-per-(twin,axis) as of runs.started_at via
--     DISTINCT ON. This + run_twins makes every run bit-for-bit replayable.
--   * matrix_cells are versioned and immutable: tuning = INSERT a new
--     version and flip the active pointer in config, never UPDATE.
--   * match_results CHECK (twin_a < twin_b) is a tripwire only — canonical
--     ordering is enforced in Lisp at the single write site. No triggers.

CREATE TABLE twins (
    twin_id    TEXT PRIMARY KEY CHECK (twin_id LIKE 'tw_%'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Registry of scoring axes as config. Gate and dealbreaker axes
-- (work-ethic, family-plans, pet-allergy, must-have-pet) are observation
-- vocabulary, not scoring axes — axis_values.axis_id is deliberately not
-- a foreign key into this table.
CREATE TABLE axes (
    axis_id TEXT PRIMARY KEY,
    scoring TEXT NOT NULL CHECK (scoring IN
        ('scalar', 'scalar-floor', 'matrix', 'tag-set', 'cross')),
    weight  NUMERIC NOT NULL DEFAULT 1.0,
    active  BOOLEAN NOT NULL DEFAULT true
);

-- Append-only observation log. Typed-value trio, exactly one non-null.
-- Normalized, NOT JSONB: tuning queries ("confidence distribution on
-- conflict-style across the pool") gate the gate.
-- Booleans ride in categorical_value as 'true'/'false'.
CREATE TABLE axis_values (
    twin_id           TEXT NOT NULL REFERENCES twins,
    axis_id           TEXT NOT NULL,
    observed_at       TIMESTAMPTZ NOT NULL,
    scalar_value      NUMERIC CHECK (scalar_value BETWEEN 0 AND 1),
    categorical_value TEXT,
    tagset_value      TEXT[],
    confidence        NUMERIC NOT NULL CHECK (confidence BETWEEN 0 AND 1),
    provenance        TEXT NOT NULL CHECK (provenance IN
                          ('observed', 'self-reported', 'inferred')),
    PRIMARY KEY (twin_id, axis_id, observed_at),
    CHECK (num_nonnulls(scalar_value, categorical_value, tagset_value) = 1)
);

-- Versioned, immutable-by-rule compatibility matrices.
-- (value_a, value_b) stored once per unordered pair, in registry order.
CREATE TABLE matrix_cells (
    axis_id      TEXT NOT NULL,
    version      INTEGER NOT NULL,
    value_a      TEXT NOT NULL,
    value_b      TEXT NOT NULL,
    score        NUMERIC NOT NULL CHECK (score BETWEEN 0 AND 1),
    finding_code TEXT,
    severity     TEXT CHECK (severity IN ('watch', 'attention', 'structural')),
    PRIMARY KEY (axis_id, version, value_a, value_b),
    CHECK ((finding_code IS NULL) = (severity IS NULL))
);

-- Knobs. All numeric on purpose; the active matrix-version pointers live
-- here too (tuning = INSERT new matrix version + flip pointer).
CREATE TABLE config (
    key   TEXT PRIMARY KEY,
    value NUMERIC NOT NULL
);

CREATE TABLE runs (
    run_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    config_snapshot JSONB NOT NULL,
    matrix_versions JSONB NOT NULL
);

-- The frozen pool per run: every twin considered (eligibility is
-- recomputed on replay from axis_values as of started_at, never stored).
CREATE TABLE run_twins (
    run_id  UUID NOT NULL REFERENCES runs,
    twin_id TEXT NOT NULL REFERENCES twins,
    PRIMARY KEY (run_id, twin_id)
);

CREATE TABLE match_results (
    run_id   UUID NOT NULL REFERENCES runs,
    twin_a   TEXT NOT NULL REFERENCES twins,
    twin_b   TEXT NOT NULL REFERENCES twins,
    score    NUMERIC NOT NULL,
    findings JSONB NOT NULL,
    PRIMARY KEY (run_id, twin_a, twin_b),
    CHECK (twin_a < twin_b)
);
