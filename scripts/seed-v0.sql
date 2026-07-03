-- LoveMotion v0 seed: axis registry, literature-seeded matrices
-- (approved 2026-07-01), and config knobs. Mirrors the in-code values in
-- src/engine.lisp; the adapter tripwires at run start if the active
-- versions here disagree with the engine's *matrix-versions*.

INSERT INTO axes (axis_id, scoring, weight) VALUES
    ('chronotype',      'scalar',       1.0),
    ('home-vs-outside', 'scalar',       1.0),
    ('conflict-style',  'matrix',       1.5),
    ('attachment',      'matrix',       1.5),
    ('ambition',        'scalar-floor', 1.0),
    ('humor',           'tag-set',      1.0),
    ('curiosity',       'scalar',       1.0);

INSERT INTO matrix_cells (axis_id, version, value_a, value_b, score, finding_code, severity) VALUES
    ('conflict-style', 0, 'direct-loud',   'direct-loud',   0.70, NULL, NULL),
    ('conflict-style', 0, 'direct-loud',   'slow-burn',     0.30, NULL, NULL),
    ('conflict-style', 0, 'direct-loud',   'avoid-explode', 0.40, NULL, NULL),
    ('conflict-style', 0, 'direct-loud',   'calm-dissect',  0.80, 'asymmetric-pairing', 'watch'),
    ('conflict-style', 0, 'slow-burn',     'slow-burn',     0.20, 'quiet-cold-war', 'attention'),
    ('conflict-style', 0, 'slow-burn',     'avoid-explode', 0.20, NULL, NULL),
    ('conflict-style', 0, 'slow-burn',     'calm-dissect',  0.60, NULL, NULL),
    ('conflict-style', 0, 'avoid-explode', 'avoid-explode', 0.15, 'mutual-detonation', 'structural'),
    ('conflict-style', 0, 'avoid-explode', 'calm-dissect',  0.50, NULL, NULL),
    ('conflict-style', 0, 'calm-dissect',  'calm-dissect',  0.90, NULL, NULL),

    ('attachment', 0, 'secure',       'secure',       0.90, NULL, NULL),
    ('attachment', 0, 'secure',       'anxious',      0.65, NULL, NULL),
    ('attachment', 0, 'secure',       'avoidant',     0.60, NULL, NULL),
    ('attachment', 0, 'secure',       'disorganized', 0.45, 'stabilizer-load', 'attention'),
    ('attachment', 0, 'anxious',      'anxious',      0.35, NULL, NULL),
    ('attachment', 0, 'anxious',      'avoidant',     0.20, 'pursue-withdraw', 'structural'),
    ('attachment', 0, 'anxious',      'disorganized', 0.20, NULL, NULL),
    ('attachment', 0, 'avoidant',     'avoidant',     0.30, 'intimacy-starved', 'attention'),
    ('attachment', 0, 'avoidant',     'disorganized', 0.25, NULL, NULL),
    ('attachment', 0, 'disorganized', 'disorganized', 0.15, 'dual-disorganized', 'structural');

INSERT INTO config (key, value) VALUES
    ('schema-version',                 1),
    ('work-ethic-floor',               0.40),
    ('work-ethic-readmit',             0.45),
    ('gate-min-confidence',            0.70),
    ('ambition-floor',                 0.30),
    ('low-band-threshold',             0.50),
    ('min-findings',                   1),
    ('max-findings',                   4),
    -- Active matrix-version pointers: tuning = INSERT new version rows
    -- above + UPDATE these pointers (the one mutable thing here).
    ('conflict-style-active-version',  0),
    ('attachment-active-version',      0);
