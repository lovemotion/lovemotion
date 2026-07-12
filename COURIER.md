# COURIER.md — the Spaces courier convention (v1 strawman)

Status: **approved by Danny 2026-07-10** (veto pass, all keep: prefix
layout, key format, cursor-not-ack handshake, 30-day retention, twin
wire shape); agreed with HeyU 2026-07-11. The Lisp side
(`src/transport.lisp`) implements exactly this document — when a line
here changes, that file changes with it.

The courier is the only thing that crosses the HeyU/LoveMotion boundary.
It moves opaque bytes on a schedule; it knows nothing about matching.
No PII crosses, ever — twin IDs (`tw_...`) are the only join key, and
they join to nothing on this side.

## Bucket

One private DigitalOcean Spaces bucket, both directions:

```
lovemotion-courier          (region: same as the droplet; config, not code)
```

Two prefixes, named by **content**, not by sender — either side can be
rewritten without renaming the wire:

| prefix | writer | reader | payload |
|--------|--------|--------|---------|
| `twins/v1/`   | HeyU       | LoveMotion | twin batches (MessagePack) |
| `matches/v1/` | LoveMotion | HeyU       | match payloads (MessagePack) |

The contract version lives **in the prefix**. A breaking wire change is
a new prefix (`twins/v2/`), never a mutation — old consumers keep
draining the old prefix until they're upgraded. Same immutability
instinct as the matrices.

## Key naming

```
matches/v1/20260704T031500Z-347cbc8e-53a9-421a-b7e9-515c101e48c3.msgpack
twins/v1/20260704T020000Z-batch-000117.msgpack
```

- UTC timestamp, basic ISO-8601 (`YYYYMMDDTHHMMSSZ`), then the
  producer's id. Integer ids are slugged and zero-padded to 6
  (`batch-000117`); string ids pass through as-is. **Lexicographic
  order = chronological order** — that single property is what the
  whole handshake rides on, and the timestamp prefix carries it
  regardless of id shape.
- The id is the producer's: `runs.run_id` for matches — a **UUID
  string**, so match keys end in the bare UUID — and HeyU's integer
  batch sequence for twins. Ids are for idempotency; timestamps are
  for ordering and human eyes.

## Handshake (there isn't one, on purpose)

A single-object PUT is atomic on S3-compatible stores: a key either
lists with its full body or doesn't exist. So:

- **No marker files, no manifests, no acks.** One payload = one object.
- Each consumer keeps a **cursor** — the last key it processed — on its
  own side (LoveMotion: a row in its Postgres; HeyU: wherever it
  likes). Poll = list the prefix, take keys strictly after the cursor,
  process in lexicographic order, advance the cursor.
- **Idempotency by id, not by key**: the run-id / batch-id inside the
  payload is the dedup key. A re-uploaded or double-listed object is a
  no-op on the consumer.
- Writes into the bucket are one-directional per prefix. Neither side
  ever writes to the prefix it reads — no two-way coupling through the
  bucket.

## Integrity

Body SHA-256 goes in object metadata as `x-amz-meta-payload-sha256`
(hex). Checking it is optional — MessagePack decode already fails loudly
on truncation. This is transport-level belt-and-braces, **not** the
rejected S3-ETag-for-matrix-integrity idea; matrices never cross the
wire at all.

## Retention

Bucket lifecycle rule expires objects after **30 days**. Consumers never
delete — a consumer that deletes is a consumer that can destroy the
other side's replay window.

## Wire shapes

Both directions are MessagePack maps with downcased string keys.

### matches (already shipping — `src/courier.lisp`, contract v1)

```
{ "contract-version": 1, "run-id": str,   # UUID from runs.run_id — NOT an int
                                          # (doc bug fixed 2026-07-12; the code
                                          # never shipped anything else)
  "matrix-versions": {"conflict-style": <int>, "attachment": <int>},
  "pool-size": <int>,
  "matches": [ { "twin-a": "tw_...", "twin-b": "tw_...",
                 "score": <float32>,
                 "findings": [ {"axis": str, "code": str,
                                "detail": num|str|[str], "severity": str} ] } ] }
```

### twins (inbound — new in this document)

```
{ "contract-version": 1,
  "batch-id":         <int>,          # HeyU's sequence, the idempotency key
  "generated-at":     <int>,          # unix epoch seconds, UTC
  "twins": [
    { "id": "tw_...",
      "axis-values": [
        { "axis":        str,          # e.g. "chronotype", "family-plans"
          "kind":        "scalar" | "categorical" | "tagset",
          "value":       float32 | str | [str],   # must match kind
          "confidence":  float32,      # REQUIRED — absent is a decode error,
                                       # never a default (iron rule)
          "provenance":  "observed" | "self-reported" | "inferred",
          "observed-at": <int> } ] } ] }
```

- `kind` is explicit and validated against the value's type on decode —
  the wire mirror of the DB's typed-value trio with its
  `num_nonnulls = 1` CHECK. Inference from MessagePack types would work
  until the first encoder bug, then fail silently.
- An axis missing from the list is simply unobserved — same semantics
  as everywhere else (never a veto, never a gate).
- Booleans (`must-have-pet`, `pet-allergy`) ride as categorical
  `"true"` / `"false"` rather than adding a fourth kind the DB trio
  doesn't have.

## Config (environment, adapter-only)

```
LM_SPACES_ENDPOINT   e.g. nyc3.digitaloceanspaces.com
LM_SPACES_REGION     e.g. nyc3
LM_SPACES_BUCKET     lovemotion-courier
LM_SPACES_KEY        access key   (Spaces keys, not DO API tokens)
LM_SPACES_SECRET     secret key
```

Domain code never sees these — they configure the transport adapter
only, same seam discipline as the DB.

## Entrypoint (LoveMotion side)

`(lovemotion.batch:courier-batch-run)` is the whole off-hours batch:
drain `twins/v1/` (cursor in `courier_cursor`, idempotency by batch-id
in `courier_batches`, one transaction per batch), then — only if
anything new arrived, or `:force-run t` — run matching and ship to
`matches/v1/`. A poison batch stops the drain loudly with the cursor
still before it; it is never skipped silently.

## Still needed before go-live

1. ~~Danny's veto pass over this document~~ ✓ (2026-07-10, all keep:
   prefix layout, key format, cursor-not-ack handshake, 30-day
   retention, twin wire shape).
2. HeyU's agreement (it writes `twins/v1/`, reads `matches/v1/`),
   its Elixir encoder, and its own scoped key.
3. ~~The bucket~~ ✓ (`lovemotion-courier`, sfo3, scoped LoveMotion key,
   live-tested 2026-07-10). ~~30-day lifecycle rule~~ ✓ (2026-07-11:
   rule `expire-30d`, whole bucket, verified by read-back). Note for
   the future: DO's bucket-scoped Spaces keys get AccessDenied on
   lifecycle config (object ops fine) and the control panel has no
   lifecycle UI — changing the rule means re-running
   `deploy/set-lifecycle.lisp` with a temporary **full-access** key,
   revoked after.
4. ~~Schedule `courier-batch-run` on the droplet~~ ✓ (systemd timer,
   nightly 03:15 UTC; `deploy/lovemotion-batch.{service,timer}`).

## zs3-vs-Spaces notes (learned the hard way, 2026-07-10)

Three DO dialect quirks, all absorbed in the adapter — `with-spaces`
in `src/transport.lisp` (first two) and `src/zs3-shim.lisp` (third):

- zs3 defaults to plain HTTP; DO 302-redirects it. HTTPS forced.
- zs3 only paths the bucket for AWS regional endpoints; for anything
  else the bucket must be baked into the endpoint (virtual-host
  style) or it never reaches the wire — DO then sees a bucketless
  request and answers `AccessDenied`.
- DO orders `ListBucketResult` elements differently from AWS
  (`Marker` trails `Contents`, `StorageClass` precedes `Owner`, extra
  `<Type>`); zs3's strict binder is re-registered with the
  differences made optional.
