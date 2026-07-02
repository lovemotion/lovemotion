# LoveMotion Finding Codes

Shared vocabulary between LoveMotion and HeyU. LoveMotion emits
machine-readable codes; **HeyU/Lexi owns all prose**. Nothing in this
document is user-facing copy — it defines what each code *means* so the
prose layer can be written and tested against stable semantics.

## Shape

Every finding is a plist:

```lisp
(:axis <axis-id> :code <code> :detail <code-specific> :severity <severity>)
```

Every match ships **at least 1 and at most 4** findings (`:min-findings`
/ `:max-findings` config). A blank maintenance schedule is a lie: all
relationships require work, so even the strongest match carries its two
relative-weakest axes as `:maintenance` items. Universal notes carry no
stigma — oil-change sticker, not recall notice.

Per-axis scores never cross the boundary. `:detail` is the only
score-adjacent data HeyU receives, and only where the code calls for it.

## Severity (exactly three levels)

| severity | meaning |
|----------|---------|
| `:watch` | Normal maintenance. Nothing is wrong; this is where routine attention goes. |
| `:attention` | A known friction pattern for this pairing. Worth deliberate practice early. |
| `:structural` | A well-documented failure dynamic for this combination. The match may still be strong overall; this dynamic needs active, ongoing management. |

Dedupe: one finding per axis, highest severity wins. Sort: severity
descending, then axis score ascending. Cap: 4.

## Universal codes (any axis)

| code | detail | fires when |
|------|--------|-----------|
| `:maintenance` | axis score (number) | Always: the two relative-weakest axes of the match, even when nothing is wrong. Severity `:watch`. |
| `:low-band` | axis score (number) | Axis scored below `:low-band-threshold` (0.50) in an otherwise-accepted match. Severity `:attention`. |

## Matrix-cell codes (pairing annotations)

These fire from specific value pairings, independent of score. `:detail`
is the pair of categorical values, e.g. `(:direct-loud :calm-dissect)`.

### `:conflict-style`

| code | pairing | severity | dynamic |
|------|---------|----------|---------|
| `:asymmetric-pairing` | direct-loud × calm-dissect | `:watch` | High-functioning but asymmetric: one processes hot, one processes cold. Works well until it doesn't; watch that neither style is being suppressed. |
| `:quiet-cold-war` | slow-burn × slow-burn | `:attention` | Two slow-burners: grievances accumulate silently on both sides with no forcing function to surface them. |
| `:mutual-detonation` | avoid-explode × avoid-explode | `:structural` | Both parties avoid until they explode; escalations synchronize with no de-escalator in the pair. |

### `:attachment`

| code | pairing | severity | dynamic |
|------|---------|----------|---------|
| `:stabilizer-load` | secure × disorganized | `:attention` | The secure partner carries a persistent stabilizing load; sustainable only if acknowledged. |
| `:pursue-withdraw` | anxious × avoidant | `:structural` | The classic pursue–withdraw loop: anxiety triggers avoidance triggers anxiety. |
| `:intimacy-starved` | avoidant × avoidant | `:attention` | Mutually comfortable distance can quietly become no intimacy at all. |
| `:dual-disorganized` | disorganized × disorganized | `:structural` | Neither partner has a reliable regulation strategy; volatility compounds. |

## Versioning

Matrix cells (and therefore which pairing codes exist) are versioned;
every payload stamps `:matrix-versions`. Adding or changing a code is a
new matrix version, never an edit to an existing one. HeyU should treat
unknown codes as forward-compatible: render generic maintenance prose
keyed on severity until the vocabulary catches up.
