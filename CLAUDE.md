# LoveMotion — Claude Code Instructions

## What This Is
LoveMotion is a standalone Common Lisp (SBCL) matching engine, Apache 2.0, air-gapped from HeyU (Elixir/Phoenix): no shared DB, no shared code. Only derived **digital twins** cross the boundary, keyed by opaque twin IDs (`tw_...`), via a DigitalOcean Spaces courier as an off-hours batch. **No PII anywhere in this system** — identity lives in a separate locked-down third system nothing here holds a foreign key into.

The engine is one deterministic pure function: twin-set → match-set. Postgres and the courier are adapters underneath fetch/persist seams; **domain code never knows about them**.

Read `Handoff.md` for the full design rationale. This file is the working summary.

## The Pipeline (locked 2026-07-01)
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
Each stage narrows or annotates; no stage reaches backward.

## Layout
```
lovemotion.asd       — :lovemotion (pure core, zero deps) + :lovemotion/test
src/
  package.lisp       — defpackage + boundary-contract header
  engine.lisp        — the whole pipeline: structs, config, axes, matrices,
                       gate, dealbreakers, scoring, findings, run-matching
  fixtures.lisp      — the golden twins (alpha/bravo/charlie), smoke-test
  courier.lisp       — MessagePack codecs: payload out, twin batches in
  transport.lisp     — courier transport: local dir + DO Spaces (zs3 shim)
  db.lisp            — Postgres adapter under the fetch/persist seams
test/
  golden.lisp        — blessed payloads + golden-test (plain equal, no framework)
site/                — static landing page for lovemotion.io (palette +
                       assets cut from lovemotion_art.png; self-contained)
FINDINGS.md          — finding-code vocabulary shared with HeyU
COURIER.md           — courier convention: bucket, keys, handshake, wire shapes
Handoff.md           — design handoff: rationale, schema design, rejected list
```

## Load & Test
```bash
# Load
sbcl --load ~/.quicklisp/setup.lisp \
     --eval "(push #p\"/home/danny/development/lovemotion/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :lovemotion)"

# Golden test (the CI step)
sbcl --non-interactive --load ~/.quicklisp/setup.lisp \
     --eval "(push #p\"/home/danny/development/lovemotion/\" asdf:*central-registry*)" \
     --eval "(asdf:test-system :lovemotion)"
```
The golden test asserts `(lovemotion:run-matching lovemotion:*fixture-twins*)` is `equal` to the blessed payload in `test/golden.lisp`. Any engine behavior change must either preserve it bit-for-bit or **consciously re-bless**: run `(lovemotion:smoke-test)`, verify the new payload by hand, paste it into `+golden-payload+`, and say so in the commit message.

## The Seven Axes (love languages was cut — do not re-add)
| axis-id | value kind | scoring | weight |
|---------|-----------|---------|--------|
| `:chronotype` | scalar 0–1 | 1 − \|a−b\| | 1.0 |
| `:home-vs-outside` | scalar 0–1 | 1 − \|a−b\| | 1.0 |
| `:conflict-style` | categorical | matrix v0 | 1.5 |
| `:attachment` | categorical | matrix v0 | 1.5 |
| `:ambition` | scalar 0–1 | scalar-floor (< 0.30 → ×0.5) | 1.0 |
| `:humor` | tag set | Jaccard — NOT embeddings | 1.0 |
| `:curiosity` | scalar 0–1 | 1 − \|a−b\| | 1.0 |

`:cross` scoring exists in the dispatcher, deliberately errors — no live axis until one earns it (candidate: emotional expressiveness give/need, combined with MIN not average).

## Dealbreaker Axes (stage 2 — vetoes, never scored)
| axis-id | values | clash rule |
|---------|--------|-----------|
| `:family-plans` | `:yes :no :open` | hard yes × hard no; `:open` collides with neither |
| `:pet-allergy` / `:must-have-pet` | boolean | allergy × must-have, both directions |
| `:substance-use` / `:substance-boundary` | use `:none :social :regular`; boundary `:none-acceptable :social-ok :no-limit` | one twin's use exceeds the other's stated boundary, both directions |
| `:sexual-requirements` / `:sexual-limits` | opaque tag sets — engine does set math only, HeyU owns tag meaning | a requirement appears on the other's hard-limit list, both directions |

Missing data on either side never vetoes (same no-gating-on-noise spirit as the eligibility gate).

## Iron Rules
- **Confidence must never silently default to 1.0.** Fixtures are 1.0 by design; real twins never are.
- **Matrices are immutable**: tuning = new version + flip active pointer, never edit. Only the ORDERING of cells is load-bearing at MVP scale; Danny has ordinal-level veto.
- **Eligibility is computed per run, never stored on the twin.** `:unassessed` (missing value or confidence < 0.70) is NEVER `:ineligible` — no gating on noise.
- **Per-axis scores never cross the boundary** — findings only (see FINDINGS.md).
- **Every match ships ≥1 finding** (universal maintenance rule). A blank schedule is a lie.
- **Pair ordering** (`twin_a < twin_b` by `string<`) enforced in Lisp at the single write site + DB CHECK as tripwire. No trigger auto-swap.
- **LoveMotion never writes prose and never calls LLMs.** HeyU/Lexi owns all prose.

## Rejected — do not re-propose
Prolog/rules engine; embedding categoricals; pgvector in the MVP loop; BEFORE INSERT pair-swap trigger; S3 ETag matrix integrity; storing eligibility on twins; love-languages axis; LoveMotion calling LLMs.

## Postgres (adapter — schema design in Handoff.md)
- `axis_values` is **append-only**: PK (twin_id, axis_id, observed_at), never UPDATE. Runs read latest-per-(twin,axis) as of `runs.started_at` via `DISTINCT ON`.
- Typed-value trio (scalar/categorical/tagset) with `CHECK num_nonnulls(...) = 1`. Normalized, NOT JSONB.
- `provenance` ∈ observed | self-reported | inferred — load-bearing (involuntary-channels thesis).
- Pipeline wraps snapshot+read in one REPEATABLE READ transaction.
- `runs` carries `config_snapshot` + `matrix_versions` JSONB; `run_twins` freezes the pool — every historical run bit-for-bit replayable.

## History
The previous architecture (13-rule engine, pgvector ANN, hunchentoot HTTP API) lives on branch `archive/rules-engine` and still runs on the droplet (systemd `lovemotion`, nginx, lovemotion.io TLS) until v0's adapters replace it. Don't build on it. Since 2026-07-10 nginx serves `site/` at `/` and proxies only `/v1/*` + `/admin/*` to the old API (:8080); redeploy with `deploy/deploy-site.sh`.

**This working directory IS the production droplet** (`ubuntu-s-1vcpu-1gb-lovemotion-01`, lovemotion.io — confirmed by machine-id 2026-07-10). Dev and prod are one box: `lovemotion_v0` here is the live DB the nightly courier batch feeds. Consequences:
- **Never run `lovemotion/db-test` or `lovemotion/batch-test` here** — they TRUNCATE the production DB. CI runs them against its own throwaway Postgres; that is the only place they run.
- `deploy/deploy-site.sh` and the `ssh lovemotion.io` in it are this box addressing itself (key `~/.ssh/lovemotion_droplet`, passwordless sudo) — harmless, and keeps working if dev ever moves off-box.
- Mind the 1 GB RAM: heavy SBCL compiles share the box with nginx, Postgres, the old API, and the 03:15 UTC batch timer.

## Next Actions (owner-approved order)
1. ~~Golden test~~ ✓ (now two blessed payloads: base + mixed-confidence)  2. ~~ASDF/repo structure + FINDINGS.md~~ ✓  3. ~~Postgres adapter~~ ✓ (`src/db.lisp`; dev DB `lovemotion_v0`; integration test `(asdf:test-system :lovemotion/db-test)` — DESTRUCTIVE truncate, needs LM_DB_PASS)
4. Courier adapter (Spaces): ~~MessagePack serialization~~ ✓ (`src/courier.lisp`, both directions); ~~transport code~~ ✓ (`src/transport.lisp` + `src/zs3-shim.lisp`, `COURIER.md` convention; test `(asdf:test-system :lovemotion/transport)`); ~~bucket + LoveMotion key~~ ✓ (sfo3, live round-trip tested 2026-07-10; creds in gitignored `.env`, load via `set -a && source .env`); ~~COURIER.md veto pass~~ ✓ (Danny, 2026-07-10, all keep); ~~batch entrypoint~~ ✓ (`src/batch.lisp`: `(lovemotion.batch:courier-batch-run)` drains twins/v1 → runs → ships matches/v1, skips the run when the courier is quiet; cursor + idempotency tables in schema; test `(asdf:test-system :lovemotion/batch-test)` — DESTRUCTIVE, needs live DB). ~~scheduling on the droplet~~ ✓ (`deploy/lovemotion-batch.{service,timer}`, nightly 03:15 UTC, first-run verified 2026-07-10; env in droplet `/etc/lovemotion/batch.env`). Go-live still needs: HeyU agreement + Elixir encoder + HeyU's scoped key, 30-day lifecycle rule on the bucket
5. v2 pile (do NOT build now): hysteresis re-admit, Life Force composite, directional curiosity, `:cross` axis, axis-pair findings, pool sharding at scale (block pairs by dealbreaker compatibility before scoring; index is adapter-layer, a pure function of append-only axis_values, invalidated per twin at drain time, and provably equivalent to recomputation — CI asserts cold-cache run ≡ warm-cache run byte-for-byte. ANN prefilter stays a last resort behind all of that)

## Working Style
Danny approves at the ordinal/architectural level; decimals live in config + literature. Propose concrete strawmen for veto, not open questions. Terse colloquial messages are normal. Leave state written down so no session re-derives.
