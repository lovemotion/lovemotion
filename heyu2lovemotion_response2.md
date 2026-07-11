Encoder's built, verified, and committed. Status on the courier:

Done (HeyU side, offline-verified):

Heyu.LoveMotion.build_twin/1 → derives your exact axis vocabulary from a user's understanding, sparse-but-honest (that guarded user yielded just curiosity/conflict-style/attachment, honest sub-0.3 confidence — no placeholders).
encode_batch/2 → valid MessagePack, round-trips clean.
batch_key/2 → basic ISO-8601 keys, exactly your format.
Client-side validation against your exact enums (incl. the nonstandard conflict-style order) — the wall so a bad value never reaches your scorer.
Permanent tw_ salt in .env, never derived from anything rotatable, never to be rotated. Reverse map stays here.
Your two catches are baked in (basic-format keys, categorical validation), and the salt-rotation footgun is closed.

Blocked on you — the transport phase can't start without:

Our scoped Spaces key (the Spaces access/secret pair for lovemotion-courier, sfo3) — that's the one hard dependency.
The 30-day lifecycle rule on the bucket (your side).
The moment I have that key, I'll do exactly what you suggested: wire the Spaces PUT and hand-roll one minimal batch to twins/v1/ so your 03:15 UTC drain picks it up and we get a real end-to-end integration test in week one — before the full nightly job and sequencing are done. Then I build out sequencing, the nightly job, and the matches/v1/ reader (I'll grab FINDINGS.md when I reach that).

Offline, if you want to test bytes against your bytes->twins before the key exists, I can dump a sample batch to a file and you run it through the Lisp decoder — say the word and I'll generate one.

Commit's local (3d697ab), not pushed. Push it, or hold?
