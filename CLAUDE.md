# LoveMotion — Claude Code Instructions

## What This Is
LoveMotion.io is a **Companion-to-Companion Pre-Connection Simulation Engine** written in Common Lisp (SBCL). It is a headless matching microservice (Apache 2.0) called by HeyU.com. It never holds PII — users are opaque `heyu_user_ref` tokens. Matching is batch-scheduled; HeyU polls for results.

## Language & Runtime
- **Common Lisp / SBCL 2.6.0** — write idiomatic CL, not "Lisp-flavored Python"
- **Quicklisp** at `~/.quicklisp` — `(ql:quickload :lovemotion)` to load the full system
- **ASDF** system definition in `lovemotion.asd`
- All CL package symbols must be explicitly managed; prefer `(:use #:cl)` + qualified references over deep `:use` chains to avoid symbol clobbering (see [Known Footgun](#known-footgun))

## Project Layout
```
src/
  config.lisp           — env-var config, all *global-params*
  database.lisp         — with-db macro (per-request postmodern connections)
  model/
    companion.lisp      — defstruct companion, upsert, eligibility query
    match-result.lisp   — store, unconsumed-matches, mark-consumed
  engine/
    rules.lisp          — defrule macro, *rule-registry*, rule/rule-result structs
    scoring.lisp        — weighted-score, cosine-similarity
    simulation.lisp     — simulate/2 — pure, stateless, gate→weighted pipeline
    rules/
      gates.lisp        — proof-of-work-gate, growth-level-window-gate, cooldown-gate
      growth.lisp       — growth-velocity-harmony, growth-level-complementarity
      contribution.lisp — mutual-contribution-orientation, proof-of-work-alignment
      values.lisp       — attachment-style-compatibility, lifestyle-axes-alignment
      readiness.lisp    — circle-engagement-signal, active-growth-readiness
      practical.lisp    — geographic-compatibility, lifestyle-investment-parity
  matching/
    pgvector.lisp       — find-candidates using <=> cosine ANN
    pipeline.lisp       — run-pipeline (logs run, loads companions, runs simulation, stores ready)
    scheduler.lisp      — bordeaux-threads timer, start-scheduler/stop-scheduler/run-now
  api/
    health.lisp         — GET /v1/health
    companions.lisp     — POST/DELETE /v1/companions
    matches.lisp        — GET /v1/matches
  server.lisp           — Hunchentoot easy-acceptor, single catch-all handler, route fn
  main.lisp             — start/stop/main entry points
test/
  package.lisp          — defpackage, def-suite :lovemotion, run-all
  fixtures.lisp         — make-test-companion, companion-a/b, with-isolated-registry
  scoring.lisp          — weighted-score and vector math tests
  rules.lisp            — registry, gate veto, attachment, geographic tests
  simulation.lisp       — end-to-end simulate/2 tests (determinism, symmetry, veto)
```

## Key Libs & Their Quirks
| Lib | Notes |
|-----|-------|
| hunchentoot 1.3.1 | `easy-acceptor`; single catch-all handler via `define-easy-handler`; explicit `(:shadow #:start #:stop)` required when using `(:use #:hunchentoot)` |
| postmodern | `with-connection` per-request only (pool API changed in v2.x); S-SQL for queries |
| jonathan | `jonathan:to-json` (NOT `jonathan:encode`); `jonathan:parse` |
| bordeaux-threads | For scheduler timer loop |
| log4cl | `(log:info ...)`, `(log:error ...)` |
| cl-ppcre | Regex URI matching |

## Database
- PostgreSQL 18, pgvector 0.8.1, uuid-ossp
- DB name/user/pass: `lovemotion` (dev); configure via env vars in prod
- Schema in `scripts/setup-db.sql`
- pgvector: `embedding vector(1536)`, ivfflat index, `<=>` operator for cosine ANN
- `(lovemotion.database:check-connection)` → T or NIL

## Environment Variables
```
LM_DB_HOST      LM_DB_PORT      LM_DB_NAME
LM_DB_USER      LM_DB_PASS      LM_HTTP_PORT
LM_API_KEY      LM_LOG_LEVEL
```

## Running

```bash
# Production (systemd — uses saved image, ~272ms startup)
sudo systemctl restart lovemotion
sudo journalctl -u lovemotion -f

# Dev (Quicklisp load — ~15s startup, no DB required)
sbcl --load ~/.quicklisp/setup.lisp \
     --eval "(push #p\"/home/danny/development/lovemotion/\" asdf:*central-registry*)" \
     --eval "(ql:quickload :lovemotion)" \
     --eval "(lovemotion:start)"

# Rebuild saved image after source changes
bash scripts/build-image.sh   # outputs bin/lovemotion (18M), then restart systemd

# Run tests
sbcl --load ~/.quicklisp/setup.lisp \
     --eval "(push #p\"/home/danny/development/lovemotion/\" asdf:*central-registry*)" \
     --eval "(asdf:test-system :lovemotion-test)" \
     --eval "(sb-ext:exit)"
```

## Auth
All `/v1/*` endpoints require `Authorization: Bearer <LM_API_KEY>`. `/v1/health` is public. `/admin/*` restricted to 127.0.0.1.

## Rules Engine
`defrule` macro in `engine/rules.lisp`. Two categories:
- **Gates** (`:category :gate`) — veto on failure, short-circuit simulation
- **Weighted** (`:category :weighted`, `:weight float`) — contribute to final score

Introduction threshold: `*introduction-threshold*` = 0.72 (configurable).

13 rules total — 3 gate + 10 weighted:

| Rule | Category | Weight |
|------|----------|--------|
| proof-of-work-gate | gate | — |
| growth-level-window-gate | gate | — |
| cooldown-gate | gate | — |
| mutual-contribution-orientation | weighted | 0.20 |
| growth-velocity-harmony | weighted | 0.15 |
| attachment-style-compatibility | weighted | 0.15 |
| circle-engagement-signal | weighted | 0.12 |
| growth-level-complementarity | weighted | 0.10 |
| proof-of-work-alignment | weighted | 0.10 |
| lifestyle-axes-alignment | weighted | 0.10 |
| active-growth-readiness | weighted | 0.08 |
| geographic-compatibility | weighted | 0.07 |
| lifestyle-investment-parity | weighted | 0.03 |

## Known Footgun
`(:use #:hunchentoot)` imports `hunchentoot:start` and `hunchentoot:stop` into the using package. `defun start` then calls `intern` which returns the *inherited* symbol — so you're redefining `hunchentoot:start` itself. Always add `(:shadow #:start #:stop)` to the defpackage when using hunchentoot and defining functions of the same name.

## Deployment (prod server)
- nginx 1.28.0: `/etc/nginx/sites-available/lovemotion.io` — HTTP→HTTPS redirect, proxy to :8080, HSTS, Let's Encrypt TLS
- systemd: `/etc/systemd/system/lovemotion.service` — enabled, `Restart=on-failure`, env from `/etc/lovemotion/env`
- Saved image: `bin/lovemotion` (18M compressed, ~272ms startup) — rebuild with `scripts/build-image.sh`
- GitHub: `git@github.com:lovemotion/lovemotion.git`

## Still TODO (Phase 2)
- Load test with synthetic companion pool (`scripts/load-test.sh`)
- FiveAM test for `run-pipeline` with a test DB
- API integration test: POST /v1/companions → GET /v1/matches round-trip
- `certbot renew --dry-run` — verify auto-renewal
- Rate limiting in nginx (protect companion ingest)
