# LoveMotion Dev Status
*Last updated: 2026-07-03*

## Where We Are

**Pivoted.** The 13-rule pgvector/HTTP system is archived on branch
`archive/rules-engine` (it still runs on the droplet untouched — systemd
`lovemotion`, nginx, lovemotion.io TLS, certbot renewal verified
2026-07-02). `main` is now the v0 engine from `Handoff.md`, redesigned
from the ground up on 2026-07-01/02.

## Done

- `Handoff.md` — full design rationale, schema design, rejected list
- v0 engine split into `src/package.lisp` / `src/engine.lisp` /
  `src/fixtures.lisp`, byte-identical to the blessed monolith
- ASDF systems: `:lovemotion` (pure core, zero dependencies) and
  `:lovemotion/test`; `(asdf:test-system :lovemotion)` runs the golden test
- Golden test (`test/golden.lisp`): blessed 2026-07-02 payload asserted
  with plain `equal`; verified it fails (exit 1, tree diff) on behavior
  change and passes (exit 0) intact
- `FINDINGS.md` — finding-code vocabulary shared with HeyU
- **Postgres adapter** (`src/db.lisp`, systems `:lovemotion/db` +
  `:lovemotion/db-test`): schema + seed in `scripts/`, append-only
  `axis_values` with typed-value trio, as-of `DISTINCT ON` fetch (coerces
  NUMERIC → single-float so DB runs are bit-identical to memory runs),
  `run_twins` snapshot, results writer, matrix-version tripwire, all in
  one REPEATABLE READ transaction; `replay-run` recomputes a historical
  run read-only. Round-trip integration test passes against the golden
  payload on dev DB `lovemotion_v0` (`(asdf:test-system :lovemotion/db-test)`
  — DESTRUCTIVE truncate, dev/test DB only; needs LM_DB_PASS)

- **Second golden payload** (mixed-confidence): fixtures delta/echo/
  foxtrot/golf cover confidence-discounted weights, :unassessed
  exclusion, dealbreaker veto, :low-band outranking :maintenance —
  blessed in `test/golden.lisp`, runs in the same
  `(asdf:test-system :lovemotion)`
- **Courier serialization** (`src/courier.lisp`, `:lovemotion/courier`):
  payload → MessagePack (maps with string keys mirroring the JSONB
  shape, float32 scores round-trip exactly; golden payload = 367 bytes);
  `write-payload-file` for local bytes. Round-trip test field-by-field
  against golden values (`(asdf:test-system :lovemotion/courier)`)

- **Dealbreaker stubs closed** (substances + sexual hard limits, same
  predicate shape): `:substance-use`/`:substance-boundary` rank clash and
  `:sexual-requirements`/`:sexual-limits` opaque-tag intersection, both
  directions, missing data never vetoes. Golden payload #3
  (`*fixture-twins-dealbreakers*`: 6 pairs, 4 vetoes, 2 matches at
  0.9625) blessed in `test/golden.lisp`. Stage 2 is contract-complete.
- **GitHub Actions CI** (`.github/workflows/ci.yml`): golden + courier +
  DB round-trip on every push/PR, Postgres 18 service container, cached
  Quicklisp. First run green.

## Next (owner-approved order — see Handoff.md)

4. **Courier adapter, second half** — DO Spaces transport (needs bucket +
   credentials + naming/handshake convention agreed with HeyU)
5. v2 pile (do not build now): hysteresis re-admit, Life Force composite,
   directional curiosity, `:cross` axis, axis-pair findings

## Known Stubs (from handoff)

1. Hysteresis needs prior-run state (`:work-ethic-readmit` reserved in config)
2. `:cross` dispatch deliberately errors
3. Dealbreakers: substances + sexual hard limits TODO (same predicate shape)
