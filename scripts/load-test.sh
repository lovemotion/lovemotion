#!/bin/bash
# Load test: seed N synthetic companions, run one pipeline pass, report timing, clean up.
# Usage: ./scripts/load-test.sh [N]   (default 10000)
set -e

N=${1:-10000}
PREFIX="load-test"
REPO=/home/danny/development/lovemotion

# ── DB creds from env file ──────────────────────────────────────────────────
source <(grep -v '^#' /etc/lovemotion/env | sed 's/^/export /')
export PGPASSWORD=$LM_DB_PASS
PSQL="psql -h ${LM_DB_HOST:-localhost} -U $LM_DB_USER -d $LM_DB_NAME -q"

cleanup() {
  echo ""
  echo "Cleaning up $N test companions..."
  $PSQL -c "DELETE FROM companions WHERE heyu_user_ref LIKE '${PREFIX}-%';" 2>/dev/null || true
  echo "Done."
}
trap cleanup EXIT

# ── Seed ────────────────────────────────────────────────────────────────────
echo "Seeding $N companions (embedding generation takes ~30s)..."
SEED_START=$(date +%s)

$PSQL <<SQL
INSERT INTO companions (
  heyu_user_ref, growth_level, proof_of_work_score, contribution_score,
  attachment_style, growth_velocity, geographic_region,
  lifestyle_axes, last_circle_signals, eligible_for_matching, snapshot_at, embedding
)
SELECT
  '${PREFIX}-' || i,
  (floor(random() * 4) + 2)::int,                           -- growth_level 2-5
  round((random() * 0.5 + 0.5)::numeric, 4),                -- proof_of_work_score 0.5-1.0
  round(random()::numeric, 4),                               -- contribution_score 0.0-1.0
  (ARRAY['secure','anxious','avoidant'])[floor(random()*3+1)::int],
  round((random() * 2 - 1)::numeric, 4),                    -- growth_velocity -1.0 to 1.0
  (ARRAY['us-east','us-west','eu-west','asia-pacific'])[floor(random()*4+1)::int],
  '{}',
  '{}',
  TRUE,
  NOW(),
  (SELECT array_agg(round(random()::numeric, 4)::real) FROM generate_series(1,1536))::vector
FROM generate_series(1, $N) AS i
ON CONFLICT (heyu_user_ref) DO NOTHING;
SQL

SEED_END=$(date +%s)
echo "Seeded in $(( SEED_END - SEED_START ))s. Running pipeline..."

# ── Pipeline run ─────────────────────────────────────────────────────────────
PIPE_START=$(date +%s)

sbcl --noinform \
     --load ~/.quicklisp/setup.lisp \
     --eval "(push #p\"$REPO/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :lovemotion :silent t)" \
     --eval "(lovemotion.config:load-config)" \
     --eval "(let ((result (lovemotion.matching.pipeline:run-pipeline)))
               (format t \"~%=== LOAD TEST RESULT ===~%\")
               (format t \"Pairs simulated : ~a~%\" (getf result :pairs-simulated))
               (format t \"Matches produced: ~a~%\" (getf result :matches-produced)))" \
     --eval "(sb-ext:exit)" 2>&1

PIPE_END=$(date +%s)
echo ""
echo "Pipeline wall time: $(( PIPE_END - PIPE_START ))s"
echo "Seed time:          $(( SEED_END - SEED_START ))s"
