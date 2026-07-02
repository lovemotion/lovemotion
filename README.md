# LoveMotion

I'm Danny — a software engineer building LoveMotion, the open-source matching engine powering HeyU.
The mechanisms by which people meet are broken so thoroughly that patching them is pointless. The world doesn't need another swipe app. It needs a fundamentally different model — one where self-improvement earns you access to people worth showing up for.

**What this is:** a behaviorally-driven matching engine that rewards genuine self-work with meaningful introductions. Not followers. Not likes. People.

## What's in this repo

A standalone Common Lisp (SBCL) engine — one deterministic pure function from a set of **digital twins** (behavioral profiles keyed by opaque IDs, no PII, ever) to a set of matches with maintenance findings:

```
twins in → eligibility gate → pair dealbreakers → 7-axis scoring
        → confidence-weighted composite → findings (never blank) → payload out
```

- **Seven axes**: chronotype, home-vs-outside, conflict style, attachment, ambition, humor, curiosity — scalars, literature-seeded compatibility matrices, and tag sets. Boring math over honest data; no embeddings, no LLMs in the loop.
- **Findings, not scores**: every match ships a small machine-readable "maintenance schedule" (see [FINDINGS.md](FINDINGS.md)). LoveMotion emits codes; the companion layer owns all prose. Per-axis scores never leave the engine.
- **Eligibility as philosophy**: low work ethic means *not yet*, not banned — and missing data is never treated as failure.
- **Reproducible by construction**: append-only observations, versioned matrices, per-run pool snapshots. Any historical run replays bit-for-bit.

Design rationale lives in [Handoff.md](Handoff.md). Test with `(asdf:test-system :lovemotion)` — the whole contract is one `equal` over one blessed payload.

## What I'm trying to figure out

How to build a credible digital twin — a behavioral model of a person — and match it meaningfully against other twins. If you've thought seriously about this problem, I want to hear from you.
Honest feedback welcome. Is it creepy? Idealistic? Does it land? Tell me.

**Collaborators:** serious engineers and people who care about getting this right. Not looking for commercial offers.

📫 dannysimonla@gmail.com · Apache 2.0 · He/Him
