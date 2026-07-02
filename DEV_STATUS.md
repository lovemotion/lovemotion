# LoveMotion Dev Status
*Last updated: 2026-07-02*

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

## Next (owner-approved order — see Handoff.md)

3. **Postgres adapter** — DDL, as-of `DISTINCT ON` fetch, `run_twins`
   insert, results writer, one REPEATABLE READ transaction around
   snapshot+read
4. **Courier adapter** (DO Spaces) — MessagePack serialization; transport
   deliberately last
5. v2 pile (do not build now): hysteresis re-admit, Life Force composite,
   directional curiosity, `:cross` axis, axis-pair findings

## Known Stubs (from handoff)

1. Hysteresis needs prior-run state (`:work-ethic-readmit` reserved in config)
2. `:cross` dispatch deliberately errors
3. Dealbreakers: substances + sexual hard limits TODO (same predicate shape)
