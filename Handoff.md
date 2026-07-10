# LoveMotion v0 — Engineering Handoff

Context: LoveMotion is a standalone Common Lisp (SBCL) matching engine at
github.com/lovemotion, Apache 2.0, on its own DigitalOcean droplet with
PostgreSQL. It is air-gapped from HeyU (Elixir/Phoenix): no shared DB, no
shared code. Only derived digital twins cross the boundary, keyed by opaque
twin IDs ("tw_..."), via a DigitalOcean Spaces courier as an off-hours batch
process. No PII anywhere in this system — aliases only; identity data lives
in a separate locked-down third system that nothing here holds a foreign key
into.

## Current state

`lovemotion-v0.lisp` exists, compiles clean on SBCL 2.2.9, and runs the full
pipeline end to end on three fixture twins. Smoke test verified:
pool-size 2 (tw_charlie gated on work ethic), one match (alpha × bravo,
0.778125), three findings emitted. Pure in-memory — no DB, no I/O, by design.

## The pipeline (locked)

```
twins in (courier)
  → eligibility gate         (work-ethic floor, confidence-guarded)
  → pair dealbreaker filters (family plans, pet allergy, substances,
                              sexual hard limits)
  → 7-axis scoring           (scalars, matrices, tag-set)
  → weighted composite       (confidence discounts weight: min(confA, confB))
  → findings generation      (min 1, max 4 per match — never blank)
  → versioned payload out    (courier)
```

Each stage narrows or annotates; no stage reaches backward. The whole engine
is a deterministic pure function twin-set → match-set. Postgres is an adapter
underneath fetch/persist seams; domain code never knows about it.

## The seven axes (love languages was cut — do not re-add)

| axis-id          | value kind  | scoring       | weight | notes |
|------------------|-------------|---------------|--------|-------|
| :chronotype      | scalar 0–1  | 1 - \|a-b\|   | 1.0    | lark→owl; observed from timestamps |
| :home-vs-outside | scalar 0–1  | 1 - \|a-b\|   | 1.0    | watch future overlap w/ social-energy axis |
| :conflict-style  | categorical | matrix v0     | 1.5    | :direct-loud :slow-burn :avoid-explode :calm-dissect |
| :attachment      | categorical | matrix v0     | 1.5    | :secure :anxious :avoidant :disorganized |
| :ambition        | scalar 0–1  | scalar-floor  | 1.0    | below :ambition-floor → base score × 0.5 |
| :humor           | tag set     | Jaccard       | 1.0    | 7 tags; NOT embeddings |
| :curiosity       | scalar 0–1  | 1 - \|a-b\|   | 1.0    | v1 note: mismatch may be asymmetric → directional later |

`:cross` scoring type exists in the dispatcher but has no live axis
(deliberately errors). Future candidate: emotional expressiveness
(give/need), combined with MIN not average — one starved direction is the
failure mode.

"Life Force" is a hypothesis, not an axis: ambition + curiosity + work
ethic may be facets of one latent trait. If real twin data shows the
correlation, it becomes a derived, versioned composite. Axes stay atomic.

## Eligibility gate (pool-level, philosophical commitment)

Low work ethic = not matchable, any mode. This is deliberate product
philosophy (HeyU is 95% self-improvement; gate = "not yet", not a ban):

- Three states: :eligible / :ineligible / :unassessed. Unassessed
  (no value, or confidence < :gate-min-confidence 0.70) is NEVER treated
  as ineligible — no gating on noise.
- Floor: work-ethic < 0.40. Hysteresis re-admit at 0.45 (config key
  reserved; needs prior-run state — currently single-threshold).
- Eligibility is COMPUTED each run, never stored on the twin. Reproducibility
  comes from the run_twins snapshot table (see schema), not a stored flag.
- v0: only :eligible twins enter the pool. Whether :unassessed twins match
  on partial data is an open product decision.

## Matrices (literature-seeded v0, approved; work estimates, not grades)

High = low predictable maintenance. Cells may carry finding annotations.
Immutable by rule: tuning = INSERT new version + flip active pointer, never
UPDATE. Only the ORDERING is load-bearing at MVP scale; decimals are the
ordering serialized. Owner has ordinal-level veto anytime.

Conflict (10 cells): dl×dl .70 | dl×sb .30 | dl×ae .40 |
dl×cd .80 (:asymmetric-pairing :watch) | sb×sb .20 (:quiet-cold-war
:attention) | sb×ae .20 | sb×cd .60 | ae×ae .15 (:mutual-detonation
:structural) | ae×cd .50 | cd×cd .90

Attachment (10 cells): sec×sec .90 | sec×anx .65 | sec×avo .60 |
sec×dis .45 (:stabilizer-load :attention) | anx×anx .35 |
anx×avo .20 (:pursue-withdraw :structural) | anx×dis .20 |
avo×avo .30 (:intimacy-starved :attention) | avo×dis .25 |
dis×dis .15 (:dual-disorganized :structural)

## Findings (the "maintenance schedule" — key product discovery)

- LoveMotion emits machine-readable finding codes; HeyU/Lexi owns ALL prose.
  LoveMotion stays deterministic, no LLM dependency, testable with `equal`.
- Finding = (:axis :code :detail :severity) with severity ∈
  :watch | :attention | :structural (exactly three levels).
- Total function: every match ships ≥1 finding (universal rule emits the two
  relative weakest axes as :maintenance :watch even in great matches).
  Rationale: all relationships require work; a blank schedule is a lie, and
  universal notes carry no stigma (oil-change sticker, not recall notice).
- Escalation rules on top: :low-band (:attention) for any axis < 0.50;
  matrix-cell annotations fire independent of score.
- Dedupe one finding per axis (highest severity wins); sort severity desc
  then axis score asc; cap 4.
- Per-axis SCORES never cross the boundary — findings only. Two reasons:
  interface discipline (else matching logic leaks into HeyU) and product
  (couples can't self-grade on numbers they never see).
- FINDINGS.md in the repo should enumerate codes/semantics — shared
  vocabulary with HeyU, doubles as public documentation.

## Boundary contract (v1, versioned from day one)

Payload out (currently s-expr; MessagePack over Spaces courier later):

```lisp
(:contract-version 1
 :run-id "..."
 :matrix-versions (:conflict-style 0 :attachment 0)
 :pool-size N
 :matches ((:twin-a "tw_..." :twin-b "tw_..."   ; canonical string< order
            :score 0.78
            :findings (...))))
```

- Non-matches and gated individuals get NOTHING (no "why no matches"
  diagnostics — ambient HeyU culture carries that signal). Matched pairs get
  findings. This asymmetry is deliberate and approved.
- Checkpoints / "six-month service interval": entirely HeyU's job using
  findings it already received. LoveMotion has NO concept of ongoing
  couples. If a fresh re-assessment is ever needed, HeyU resubmits the pair
  through the normal front door.

## Postgres schema (designed, not yet built)

Tables: twins (opaque IDs + timestamps only), axes (registry as config),
axis_values, matrix_cells (versioned), config (key/value knobs), runs
(with config_snapshot JSONB + matrix_versions JSONB for reproducibility),
run_twins (run_id, twin_id — the frozen pool per run), match_results
(run_id, twin_a, twin_b, score, findings JSONB, CHECK twin_a < twin_b).

Critical decisions:
- axis_values is APPEND-ONLY: PK (twin_id, axis_id, observed_at), never
  UPDATE. Each run reads latest-per-(twin,axis) as of runs.started_at via
  DISTINCT ON. This + run_twins makes every historical run bit-for-bit
  replayable AND gives twin history free (confidence evolution is the
  behavioral thesis).
- axis_values has typed-value trio (scalar_value NUMERIC 0–1,
  categorical_value TEXT, tagset_value TEXT[]) with
  CHECK num_nonnulls(...) = 1. Normalized, NOT JSONB — tuning queries
  ("confidence distribution on conflict-style across pool") gate the gate.
- confidence NUMERIC NOT NULL — must never silently default to 1.0.
- provenance ∈ observed | self-reported | inferred (load-bearing for the
  involuntary-channels thesis: prefer observation channels that can't be
  gamed by aspiration — that's the moat).
- Pipeline wraps snapshot+read in one REPEATABLE READ transaction.
- Pair ordering enforced in Lisp at the single insert site + CHECK as
  tripwire. NO trigger auto-swap (rejected: invisible DB magic).
- No pgvector in the MVP loop. No embeddings for categorical/ordinal values.

## Rejected — do not re-propose

- Prolog / rules engine: filters are one-level conjunctions, matrices are
  lookups; plain CL predicates + alists. Revisit only if chained inference
  is genuinely needed.
- Embedding categoricals (chronotype etc.): scalar math beats round-trips.
- BEFORE INSERT trigger for pair swap.
- S3 ETag/blob-hash matrix integrity: matrices are versioned config rows;
  append-only-by-rule suffices.
- Storing eligibility (banned flag) on twins.
- Love-languages axis (pop-psych taxonomy, no behavioral signal path).
- LoveMotion writing prose or calling LLMs. Ever.

## Known stubs in lovemotion-v0.lisp

1. Hysteresis needs prior-run state (config key reserved).
2. :cross dispatch deliberately errors.
3. ~~Dealbreakers: substances + sexual hard limits~~ done (commit 8c7bc7f).
4. smoke-test prints; not yet a golden `equal` assertion.

## Next actions, ranked

1. Golden test: bless the current smoke-test payload as canonical, assert
   with `equal`. Makes all subsequent change safe. (Owner approved this
   ordering.)
2. ASDF system + repo structure for github.com/lovemotion; FINDINGS.md.
3. Postgres adapter: DDL migration, as-of DISTINCT ON fetch, run_twins
   insert, results writer — wrapped around the pure core, REPEATABLE READ.
4. Courier adapter (Spaces): payload serialization (MessagePack), transport
   deliberately last.
5. v2 pile (do not build now): checkpoint re-issue source tags, Life Force
   composite, directional curiosity, emotional-expressiveness :cross axis,
   axis-pair findings, severity-ordered coaching sequences.

## Working style notes

Owner: ~30 yrs experience (C++/Go/TS/Elixir/CL), boring-proven-solutions
doctrine, wants pushback on weak reasoning not validation, approves at the
ordinal/architectural level and delegates decimals to config + literature.
Occasionally routes drafts through other models (DeepSeek) — triage those
contributions on merit; both prior accepted fixes were append-only-ness,
both rejections were cleverness. Matrices/thresholds are Danny-judgment
content: propose concrete strawmen for veto rather than asking open
questions. Sessions are bursty (family, day job) — always leave state
written down like this so no session starts with re-derivation.