# Reply to HeyU sign-off (draft, 2026-07-11)

All four flags answered, no blockers. Start with the encoder.

## Your flags

**1. float32 vs float64 — non-issue, don't force anything.** The decoder
validates *kind*, not float width: a `scalar` or `confidence` just has to
decode to a number (`realp` check), then it's coerced to single-float on
our side (`wire->value` / `wire->axis-value` in `src/courier.lisp`).
Msgpax's default float64 (`0xcb`) is accepted as-is. "Validated against
the MessagePack type" means map-vs-string-vs-array-vs-number — a string
where a scalar should be fails; a wider float does not.

**2. Twin-ID stability — yes, that's the contract.** Same person ⇒ same
`tw_` every batch, forever. Cross-run identity rides on it: axis history
is append-only keyed by twin_id, runs read latest-value-per-(twin, axis),
and match results only make sense to you if the id round-trips. Corollary:
**never rotate the HMAC salt** — a rotation looks to us like the entire
user base churning and all history orphans. Reverse map staying on your
side only is exactly the design.

**3. `inferred` is first-class.** Provenance is stored (it's load-bearing
for future analysis) but carries **zero weight in v0 scoring** — no
down-weighting exists to fear. Confidence is the only uncertainty channel:
each axis's weight in the composite is discounted by min(confA, confB),
and the eligibility gate treats confidence < 0.70 as `:unassessed`, which
is never `:ineligible` (no gating on noise). So honest low confidence is
safe — it shrinks influence, never punishes. Sparse-but-honest is exactly
what the pipeline was built for; missing axes never veto and never gate.

**4. Blast radius — acknowledged, staying loud-never-skip.** A poison
batch halts the drain with the cursor still *before* it — nothing is
skipped, nothing half-loads, and once the bad object is replaced the next
nightly run resumes from the cursor. So the failure mode is "one night
late," not "parked until someone notices." Your strict client-side
validation plus our strict decode is the double wall; quarantine lane
stays on the someday list.

## Two things to nail on your side (cheap now)

- **Key timestamps are *basic* ISO-8601** — `20260704T020000Z`, no dashes
  or colons: `twins/v1/20260704T020000Z-batch-000117.msgpack`. Your note
  said `<ISO8601Z>`; extended format with colons would violate the
  convention (and colons in S3 keys are misery anyway). `batch-id` in the
  payload is an int.
- **Categorical vocabulary is NOT validated at decode** — the decoder
  interns any string, and a value outside our matrix vocabulary errors
  hours later at scoring time and kills that night's run. Validate
  client-side against the exact sets:
  - `attachment`: `secure | anxious | avoidant | disorganized` (as you had)
  - `conflict-style`: `direct-loud | slow-burn | avoid-explode | calm-dissect`
    (nonstandard — ours, not Thomas-Kilmann)
  - `family-plans`: `yes | no | open`
  - `substance-use`: `none | social | regular`;
    `substance-boundary`: `none-acceptable | social-ok | no-limit`
  - booleans (`pet-allergy`, `must-have-pet`) ride as categorical
    `"true"` / `"false"` — no boolean kind on the wire
  - `humor`, `sexual-requirements`, `sexual-limits`: opaque tag sets, any
    strings — you own the meanings
  - scalars (`chronotype`, `home-vs-outside`, `ambition`, `curiosity`):
    0–1

## Confirms

- **Msgpax + ExAws: fine** — your side, your deps.
- **Severity vocabulary confirmed**: `watch | attention | structural`,
  exactly three. FINDINGS.md attached/available now — no need to wait for
  the matches reader; unknown-code forward-compat is the right call.
- **Sequencing: encoder first, yes** — with one tweak: as soon as the
  Spaces plumbing can PUT at all, ship one hand-rolled minimal batch (one
  twin, one axis-value) to `twins/v1/` before the full encoder is done.
  The nightly drain at 03:15 UTC picks it up automatically and either
  decodes or fails loudly — so the first integration test happens in week
  one, not on encoder-completion night. Our decoder (`bytes->twins`) is
  the executable spec if you want to test bytes against it offline first.

Still owed from us: your scoped Spaces key, and the 30-day lifecycle rule
on the bucket.
