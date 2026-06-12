# LoveMotion Dev Status
*Last updated: 2026-06-12*

## What's Done

### Environment
- SBCL 2.6.0 installed
- Quicklisp installed at ~/.quicklisp, wired into ~/.sbclrc
- 2GB swapfile created and persisted
- PostgreSQL lovemotion database created with pgvector + uuid-ossp extensions
- Database schema applied: companions, match_results, simulation_log tables
- All Quicklisp deps installed: hunchentoot, postmodern, jonathan, bordeaux-threads, log4cl, cl-ppcre

### Code — All Files Written
- lovemotion.asd (ASDF system definition)
- src/config.lisp
- src/database.lisp (per-request connections via with-db)
- src/model/companion.lisp
- src/model/match-result.lisp
- src/engine/rules.lisp (DEFRULE macro, rule registry)
- src/engine/scoring.lisp (weighted-score, cosine-similarity)
- src/engine/simulation.lisp (simulate function — pure, stateless)
- src/engine/rules/gates.lisp (proof-of-work-gate, growth-level-window-gate, cooldown-gate)
- src/engine/rules/growth.lisp (growth-velocity-harmony, growth-level-complementarity)
- src/engine/rules/contribution.lisp (mutual-contribution-orientation, proof-of-work-alignment)
- src/matching/pipeline.lisp
- src/matching/pgvector.lisp
- src/matching/scheduler.lisp
- src/api/health.lisp
- src/api/companions.lisp
- src/api/matches.lisp
- src/server.lisp
- src/main.lisp

### System Load Status
`(ql:quickload :lovemotion)` → **SYSTEM-LOAD-OK** ✓

All packages load and compile cleanly.

## Currently Blocked On

**Hunchentoot server start fails at runtime** with:
```
invalid number of arguments: 1
(HUNCHENTOOT:START #<HUNCHENTOOT:EASY-ACCEPTOR (host *, port 8080)>)
```

This is a Hunchentoot v1.3.1 API issue. `hunchentoot:start` is being called with 1 argument (the acceptor) but throwing "invalid number of arguments: 1". This is paradoxical. Suspect one of:
1. The `define-easy-handler` with lambda URI predicate is registering badly and causing a method resolution conflict
2. Hunchentoot 1.3.1 changed its start API
3. The `*dispatch-table*` setup is conflicting with something

### Next Debug Step (resume here after /compact)
Run a **minimal** Hunchentoot start test to isolate whether the issue is Hunchentoot itself or our handler registration:

```lisp
;; /tmp/ht-minimal.lisp
(load "/home/danny/.quicklisp/setup.lisp")
(ql:quickload :hunchentoot :silent t)
(defvar *a* (make-instance 'hunchentoot:easy-acceptor :port 9999))
(hunchentoot:start *a*)
(format t "STARTED~%")
(sleep 2)
(hunchentoot:stop *a*)
```

If this works → the issue is in our handler definition (likely the lambda URI in define-easy-handler).
If this fails → Hunchentoot 1.3.1 has a different start API.

The fix is likely one of:
- Remove the lambda URI form from define-easy-handler and use a simple catch-all dispatcher instead
- Switch from easy-acceptor to acceptor with a custom `acceptor-dispatch-request` method

## File Layout
```
/home/danny/development/lovemotion/
├── PLAN.md                    ← architecture + phases
├── DEV_STATUS.md              ← this file
├── lovemotion.asd
├── src/
│   ├── config.lisp
│   ├── database.lisp
│   ├── main.lisp
│   ├── server.lisp            ← BLOCKED (hunchentoot start issue)
│   ├── model/
│   │   ├── companion.lisp
│   │   └── match-result.lisp
│   ├── engine/
│   │   ├── rules.lisp
│   │   ├── scoring.lisp
│   │   ├── simulation.lisp
│   │   └── rules/
│   │       ├── gates.lisp
│   │       ├── growth.lisp
│   │       └── contribution.lisp
│   ├── matching/
│   │   ├── pipeline.lisp
│   │   ├── pgvector.lisp
│   │   └── scheduler.lisp
│   └── api/
│       ├── health.lisp
│       ├── companions.lisp
│       └── matches.lisp
├── test/
├── config/
└── scripts/
    └── setup-db.sql
```

## Open Architecture Questions (from earlier discussion)
| Question | Assumption used |
|----------|-----------------|
| LoveMotion own PostgreSQL? | YES — separate DB, HeyU pushes snapshots |
| How HeyU gets matches? | Polls GET /v1/matches?since= |
| Who generates embedding? | HeyU (via OpenRouter), sends to LoveMotion |
| Embedding dimensions? | 1536 (configurable) |
| Auth method? | Shared API key |
| Match schedule? | Configurable interval, default 24h |

## Missing Rules Files (still to write)
- src/engine/rules/values.lisp
- src/engine/rules/readiness.lisp
- src/engine/rules/practical.lisp

## nginx / TLS (not started yet)
- Phase 0 task: configure lovemotion.io vhost and wire Let's Encrypt cert
