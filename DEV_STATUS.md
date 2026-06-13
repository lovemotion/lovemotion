# LoveMotion Dev Status
*Last updated: 2026-06-12*

## What's Done

### Environment
- SBCL 2.6.0, Quicklisp (~/.quicklisp), 2GB swapfile
- PostgreSQL lovemotion DB, pgvector + uuid-ossp extensions, schema applied
- All Quicklisp deps installed: hunchentoot, postmodern, jonathan, bordeaux-threads, log4cl, cl-ppcre, fiveam

### Infrastructure
- nginx 1.28.0 running; `/etc/nginx/sites-available/lovemotion.io` — HTTP→HTTPS redirect, proxy to :8080, HSTS, Let's Encrypt TLS (cert already issued, cert lives at `/etc/letsencrypt/live/lovemotion.io/`)
- systemd unit at `/etc/systemd/system/lovemotion.service` — enabled, `Restart=on-failure`
- Env file at `/etc/lovemotion/env` (chmod 640 root:danny) — **fill in real LM_DB_PASS and LM_API_KEY before starting**
- GitHub remote wired: `git@github.com:lovemotion/lovemotion.git`
- Deploy key generated at `~/.ssh/lovemotion_github` — **still needs to be added to github.com/lovemotion/lovemotion → Settings → Deploy keys**

### Code — All Files Written
- `lovemotion.asd` — ASDF system, full load order including all 6 rules/ files
- `lovemotion-test.asd` — FiveAM test system
- `src/config.lisp` — all config from env vars
- `src/database.lisp` — `with-db` macro (per-request postmodern connections)
- `src/model/companion.lisp` — defstruct companion, upsert, eligibility, `make-companion` exported
- `src/model/match-result.lisp` — store, unconsumed-matches, mark-consumed
- `src/engine/rules.lisp` — `defrule` macro, `*rule-registry*`, `make-rule-result` exported
- `src/engine/scoring.lisp` — `weighted-score`, `cosine-similarity`, `dot-product`, `vector-magnitude` **(take lists, not arrays)**
- `src/engine/simulation.lisp` — `simulate/2` — pure, stateless, gate→weighted pipeline
- `src/engine/rules/gates.lisp` — proof-of-work-gate, growth-level-window-gate, cooldown-gate
- `src/engine/rules/growth.lisp` — growth-velocity-harmony, growth-level-complementarity
- `src/engine/rules/contribution.lisp` — mutual-contribution-orientation, proof-of-work-alignment
- `src/engine/rules/values.lisp` — attachment-style-compatibility, lifestyle-axes-alignment
- `src/engine/rules/readiness.lisp` — circle-engagement-signal, active-growth-readiness
- `src/engine/rules/practical.lisp` — geographic-compatibility, lifestyle-investment-parity
- `src/matching/pgvector.lisp` — ANN candidate search with `<=>` cosine operator
- `src/matching/pipeline.lisp` — run-pipeline: log → load → ANN → simulate → store
- `src/matching/scheduler.lisp` — bordeaux-threads timer, start/stop/run-now
- `src/api/health.lisp`, `src/api/companions.lisp`, `src/api/matches.lisp`
- `src/server.lisp` — Hunchentoot easy-acceptor, catch-all handler + internal route dispatch
- `src/main.lisp` — start/stop/main
- `test/package.lisp`, `test/fixtures.lisp`, `test/scoring.lisp`, `test/rules.lisp`, `test/simulation.lisp`

### Rules registry: 13 rules
- **3 gate rules** (veto): proof-of-work-gate, growth-level-window-gate, cooldown-gate
- **10 weighted rules**: growth-velocity-harmony (0.15), growth-level-complementarity (0.10), mutual-contribution-orientation (0.20), proof-of-work-alignment (0.10), attachment-style-compatibility (0.15), lifestyle-axes-alignment (0.10), circle-engagement-signal (0.12), active-growth-readiness (0.08), geographic-compatibility (0.07), lifestyle-investment-parity (0.03)

### System Load / Server Status
- `(ql:quickload :lovemotion)` → **SYSTEM-LOAD-OK** ✓
- `(lovemotion:start)` → DB verified, HTTP server up on :8080, clean shutdown ✓
- `GET /v1/health` → `{"status":"ok","version":"0.1.0","database":"connected","scheduler":"running"}` ✓
- `GET /v1/matches` (no token) → 401 ✓
- `GET /v1/matches` (Bearer token) → 200 ✓
- **systemd service active (running)** — `sudo systemctl status lovemotion`
- API key in `/etc/lovemotion/env` as `LM_API_KEY`

### Git
- 4 commits on `main`, pushed to `git@github.com:lovemotion/lovemotion.git`
- Deploy key at `~/.ssh/lovemotion_github` (write access confirmed)

## Test Suite Status (77/78 passing)

`(asdf:test-system :lovemotion-test)` or `(lovemotion.test:run-all)`

**1 remaining failure** (trivial arithmetic error in test):
```
DOT-PRODUCT-BASIC: test expects 11.0, correct answer is 12.0
Fix: change (is (= 11.0 ...)) to (is (= 12.0 ...)) in test/scoring.lisp line ~last
```

All other tests pass:
- Scoring: 11/12 (the one failure above)
- Rules: 30/30 ✓ (registry, gate veto, attachment, geographic, etc.)
- Simulation: 36/36 ✓ (gate veto, strong pair, determinism, symmetry)

**Key test design note**: `make-stub-result` in `test/fixtures.lisp` registers stubs in `*rule-registry*`. Any test that calls it MUST be wrapped in `(with-isolated-registry ...)` to prevent registry pollution of subsequent tests. The scoring tests already do this correctly.

## File Layout
```
/home/danny/development/lovemotion/
├── PLAN.md
├── DEV_STATUS.md
├── CLAUDE.md
├── lovemotion.asd
├── lovemotion-test.asd
├── .gitignore
├── src/ (all files written — see above)
├── test/
│   ├── package.lisp
│   ├── fixtures.lisp    ← with-isolated-registry macro here
│   ├── scoring.lisp
│   ├── rules.lisp
│   └── simulation.lisp
├── config/
└── scripts/
    └── setup-db.sql
```

## Next Steps

### Phase 1 Complete ✓
- Saved image built (`bin/lovemotion`, 18MB), systemd updated — startup ~3s vs ~15s
- Two runtime bugs fixed: pgvector param passing, postmodern `:NULL` coercion in `row->companion`
- Load test run: 10k companions → 265,682 pairs → 108 matches in **19 minutes**
  - Bottleneck: 10k sequential ANN queries to Postgres (one per companion)
  - Decision: acceptable for now — real eligible pool will be much smaller than 10k
  - Future option if needed: batch ANN lookups or cap eligible pool per run

### Phase 2
- FiveAM test for `run-pipeline` with a mocked DB (or test DB)
- API integration test: POST /v1/companions → GET /v1/matches full round-trip
- Certbot auto-renewal cron check (`certbot renew --dry-run`)
- Rate limiting in nginx (protect companion ingest from abuse)

## Key Gotchas (from experience)
| Symptom | Fix |
|---------|-----|
| `invalid number of arguments: 1` on `hunchentoot:start` | Add `(:shadow #:start #:stop)` to `defpackage` when `(:use #:hunchentoot)` — `defun start` otherwise clobbers `hunchentoot:start` |
| `jonathan:encode` not found | Correct function is `jonathan:to-json` |
| postmodern `"invalid number of arguments: 6"` | Use `with-connection` list form only — no persistent connect/disconnect in v2.x |
| `local-time` not in deps | Use PostgreSQL `(:now)` via S-SQL instead |
| Vector math type error | `cosine-similarity`/`dot-product`/`vector-magnitude` take **lists**, not arrays |
| Test registry pollution | Wrap `make-stub-result` calls in `with-isolated-registry` |
