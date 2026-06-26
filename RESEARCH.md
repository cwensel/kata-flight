# RESEARCH - Kata Flight Reference Surface

Kata Flight is primarily operational glue around the `kata` and `roborev` CLIs.
Its research surface is narrower than RDR: the skills need reliable workspace
binding, context grounding before state changes, and disciplined citations when
they hand work into RDRs or tracker comments.

## Optional Corpora

Use relevant Arcaneum corpora when a skill needs outside references, prior art,
or quotes for an RDR-bound decision. Discover local corpora with
`arc corpus list`; do not assume a fixed corpus set exists on every machine.

These corpora are optional research routes, not runtime dependencies. The only
runtime CLIs this repo assumes are `kata` and `roborev`.

## Tool References

- `kata` documentation: <https://katatracker.com/>
- `kata` source: <https://github.com/kenn-io/kata>
- `roborev` documentation: <https://roborev.io/>
- `roborev` source: <https://github.com/kenn-io/roborev>
- `rdr` source (optional binding): <https://github.com/cwensel/rdr>
- `arc` (Arcaneum) source (optional corpus search): <https://github.com/cwensel/arcaneum>

## Citation Hygiene

- Search results are not citations. Open the source before using a quote or
  claim.
- Prefer stable anchors: DOI, arXiv ID, URL, page, section, or `path::Symbol`.
- Keep quotes short and exact. If exact wording is unnecessary, paraphrase and
  cite the source.
- Do not cite this skill repo as evidence for claims about a consumer codebase,
  dependency, standard, or RDR. Read the owning source.

## Sources To Reuse From RDR

For RDR-specific methodology, defer to the bound RDR engine's `RESEARCH.md`.
Kata Flight should not duplicate the full RDR bibliography; it should point at
the RDR binding when the work becomes an RDR design or implementation question.
