---
name: rdr-seed-triage
argument-hint: <short-id…> | --label <name> | --all [--confirm]
description: 'Use to triage kind:rdr-seed kata backlog before running rdr-seed. Classifies seeds as one-RDR, split, collapse, demote, out-of-scope, or parked. Trigger for review/dedupe RDR seeds.'
---

# rdr-seed-triage

Triage the `kind:rdr-seed` backlog into RDR-shape dispositions, **before** any
seed is handed to `/rdr-seed`. After many `kata-scope-review` passes (and roborev
spin-offs), `kind:rdr-seed` katas accumulate in the human inbox; this skill drains
that pile in an **independent session** — no flight, no ship — and decides which
seeds are actually one well-shaped RDR, which are several entangled contracts that
must split, which are facets of one contract that should collapse, which were
over-eager seeds that belong back in the bug flow, and which are already moot.

It is the **kata-side precursor to `/rdr-seed`**. `/rdr-seed` (RDR flow Stage 1)
assumes its input is already one well-bounded design fork — it allocates a number
and writes a skeleton, no shape question asked. This skill is what makes that
assumption true: it leaves each surviving seed as a clean `/rdr-seed <id>` input
with its load-bearing contract named, so Stage 1's "is it RDR-shaped?" gate passes
instead of re-litigating shape.

## Relationship to kata-scope-review (it shares the engine, it does not replace it)

`kata-scope-review` and this skill are **two ends of one pipe**, and the boundary
is deliberate — do not merge them:

- `kata-scope-review` is the **ship pre-flight gate**. Over *raw* open katas it
  decides shippability, and routes design-forks **to** `kind:rdr-seed` as a
  terminal verdict (it then **skip-filters** `kind:rdr-seed` — a seed is, to it,
  already-handled output). It is invoked by `kata-flight`'s default review gate
  (suppressed only by `--no-review`). **Untouched by
  this skill** — the safety/gate role is preserved exactly.
- **This skill** consumes the `kind:rdr-seed` population scope-review produced and
  asks the *next* question: of these seeds, which are real RDRs vs split vs
  collapse vs demote vs moot?

Because the machinery is ~80 % shared, this skill **cites `kata-scope-review`'s
sections by `§<anchor>` rather than restating them** (the same cite-don't-clone
pattern scope-review uses for `roborev-triage`). Read `kata-scope-review` once;
the references below assume it. What differs is the **input population**
(`kind:rdr-seed`, not raw katas), the **verdict taxonomy** (RDR-shape dispositions,
not ship verdicts), and the **posture** (read-mostly shape analysis, not
source-verifying shippability).

## Usage

```
/rdr-seed-triage <short-id> [<id> …]   # specific seeds
/rdr-seed-triage --label <name>        # kind:rdr-seed ∩ <label> (e.g. an area:* slice)
/rdr-seed-triage --all                 # the whole open kind:rdr-seed backlog (drain the inbox)
/rdr-seed-triage --confirm             # human-gate the irreversible verdicts (split/demote/close)
```

**No arguments → print this Usage and stop** (a bare invocation must not fan out
across the whole backlog). `--all` is the explicit "drain the inbox" selector. A
selector resolving empty → refuse. Multiple selectors → union, deduped. This is the
inverse of scope-review's Phase 0: where scope-review *skips* `kind:rdr-seed`, this
skill *selects* it.

## Verdict taxonomy (RDR-shape dispositions)

| Verdict | Meaning | Routes to |
|---|---|---|
| `ONE-RDR` | a single, well-bounded design fork — one load-bearing contract | ready: `/rdr-seed <id>`, contract named in the seed |
| `SPLIT` | one seed entangles **>1 independent** load-bearing contract | **N child seeds**, one per contract; original converted |
| `COLLAPSE` | **K seeds** are facets of **one** underlying contract (a sub-agent proposes `COLLAPSE-CANDIDATE` / `FACET-OF`; the orchestrator confirms the COLLAPSE in Phase 3) | one survivor seed (folds the rest); `/rdr-seed <survivor>` |
| `DEMOTE` | **not** a design fork — one obvious implementation, nothing to weigh | strip `kind:rdr-seed` → back to the bug flow (the `type:*` underneath re-activates it) |
| `OUT-OF-SCOPE` | superseded by a landed RDR, adjudicated, or unreachable | `kata close` |
| `LEAVE-PARKED` | an **umbrella / container** of other seeds, or a deliberately deferred seed (`meta:*`, `umbrella`, or a parked-release marker) — not itself a single fork | leave as-is, surface; never route to `/rdr-seed` |

The deciding test for `ONE-RDR` vs `SPLIT` is **contract count, not size** — the
same proportionality test the RDR template's Normative Contracts section carries.

## Invariants

- **Sub-agents propose a shape verdict + named contract; the orchestrator
  disposes.** Same single-writer discipline as scope-review (its *Invariants*): a
  grounding sub-agent sees one seed, so it cannot decide a COLLAPSE (mutual facets
  would each name the other and race) — it flags `FACET-OF`; Phase 3 clusters and
  disposes. The orchestrator is the sole writer of every kata mutation.
- **Conservative bias = keep the fork, keep the seed.** The costly error is
  erasing a real design fork or splitting one that was whole. Undecided
  one-vs-split → **ONE-RDR** (the RDR flow can still split it later, cheaper than a
  wrong split here). Undecided collapse → do **not** merge; leave the seeds
  separate. Undecided demote → keep `kind:rdr-seed`. Undecided out-of-scope → keep
  open + surface. Undecided umbrella-vs-fork → **LEAVE-PARKED**.
- **Never strand a dependent.** Reuse `§dependent-guard` verbatim before any close
  (DEMOTE strips a label and is safe; COLLAPSE-close and OUT-OF-SCOPE-close run the
  guard).
- **Name the contract on every survivor.** ONE-RDR/SPLIT/COLLAPSE each leave the
  surviving seed(s) with a one-paragraph **Load-Bearing Contract** in the body:
  *what must be decided once* (the fork), in the carrier-vs-shape / identity /
  format / predicate vocabulary the RDR template uses. This is the payload
  `/rdr-seed` consumes — it is the whole point of the gate.
- **Read-mostly.** Auto-apply the *reversible* routing (label add/strip incl.
  DEMOTE, contract comment). **Surface the destructive** (COLLAPSE-close,
  OUT-OF-SCOPE-close, SPLIT fan-out) under `--confirm`. Posture closer to
  `kata-flow-ops` than to scope-review's autonomous closes.

## Phase 0 — Locate & resolve

**Run this resolver verbatim** (same worktree-safe derivation as `kata-scope-review`
Phase 0 step 1 — inlined, not paraphrased, because it is load-bearing). The
`.kata-flight-workspace` marker is at the **workspace root** (`workspace root`) — **two**
`dirname`s up, not the repo root; sourcing it exports the RDR-corpus paths:

```sh
PRIMARY_ROOT=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")
[ -f "$PRIMARY_ROOT/.kata-flight/env" ] && . "$PRIMARY_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$PRIMARY_ROOT")}"
[ "$(basename "$PRIMARY_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$PRIMARY_ROOT" >&2; exit 1; }
WS=$(dirname "$PRIMARY_ROOT")   # workspace root (workspace root) — worktree-invariant
KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
[ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
[ -f "$RDR_ENV" ] || { echo "stopped:no-rdr-env:$RDR_ENV (marker not sourced?)" >&2; exit 1; }
```

Then:

1. **Resolve the seed set.** `--all` → `kata list --status open --label
   kind:rdr-seed --json` (the whole backlog). Explicit ids → trusted (confirm each
   carries `kind:rdr-seed`; if not, note it but still triage — a human asked).
   `--label X` → the `kind:rdr-seed` set intersected with `X`. Union + dedup.
   **No selector at all → print Usage and stop** (never default to the whole
   backlog implicitly).
2. **Skip filters** (log counts): `owner != null` (someone is actively authoring
   its RDR); and any seed whose RDR is **already allocated** — an existing
   `process/` RDR names this kata id **in its seed field** (`Related Issues: kata
   <id> (seed…)` or equivalent; match the seed line, **not** a free-text mention —
   a follow-up cited in an RDR's See-also is still triable). An authored RDR means
   Stage 1 already ran, nothing to triage.
3. Surface the worklist + count + skip reasons once. Empty resolved set → refuse.

## Phase 1 — Pre-cluster (orchestrator, cheap)

`kata list --status open --json` once. Two cheap signals feed the Phase-2 briefs:

1. **Overlap clusters** — group the seed set by `(area:*, title gist, cited
   `path::Symbol`/concept)`, attaching candidate `FACET-OF` hints — the COLLAPSE
   head-start. This is **`§seam-accretion count`** (scope-review Phase 1) pointed
   at *seeds*: ≥2 seeds on the same seam/concept is the COLLAPSE signal, the same
   "missing design decision, not missing patch" tripwire.
2. **Parent-RDR resolution** — per seed, resolve the existing RDR it references (a
   seed almost always cites one). Pre-read its path from `$RDR_ENV`'s RDR dir so
   sub-agents verify the relationship rather than re-discover it — and so
   OUT-OF-SCOPE (a landed RDR already adjudicated this) is cheap to detect.
3. **Umbrella pre-flag** — a seed carrying `umbrella`, `meta:*`, or whose body is a
   container/parked-plan marker is flagged `LEAVE-PARKED` here and not sent for a
   shape verdict (it has no single fork to weigh).

## Phase 2 — Ground & classify (one sub-agent per seed, parallel/chunked)

Spawn one `general-purpose` sub-agent per seed running the **§Seed-shape prompt**
below. **Read-mostly grounding** (the key divergence from scope-review): the
sub-agent reads the seed's own claims, its referenced parent RDR(s), and the
shape-relevant corpus — it does **not** re-verify a defect reproduces in source
(that is shippability, scope-review's job, not shape). Same leaf-agent
verdict-only contract and chunked fan-out as scope-review `§Phase 2`.

### Seed-shape prompt

Fill `{…}` from Phase 0/1. Terse; spend tokens on the shape decision, not narration.

```text
You are shape-triaging ONE kind:rdr-seed kata to decide if it is ready for the RDR
flow (/rdr-seed). Read-only on code. Output the verdict block only.

SEED {id}: {title}
CLAIM / FORK (verbatim from body): {claim}
REFERENCED RDR(s): {rdr_paths}  ·  candidate facet-siblings: {facet_ids}

DECIDE the RDR-shape, in this order — stop at the first that fires:
0. CONTAINER? Is this an umbrella/parked-plan seed (collects other seeds, or is a
   deferred container, not itself one fork)? → LEAVE-PARKED. Do not force a fork.
1. STILL A FORK? Is there a real, open design decision with >1 defensible answer?
   If there is one obvious implementation and nothing to weigh → DEMOTE (it is a
   plain kata, not an RDR; the RDR flow would demote it at Stage 1 anyway). If a
   referenced RDR (or a landed one) already DECIDED this fork → OUT-OF-SCOPE.
2. HOW MANY CONTRACTS? Count the INDEPENDENT load-bearing contracts this seed is
   the sole author of (a distinct identity / wire-format / naming / predicate /
   type / policy each count as one — the RDR template's Normative-Contracts test).
   Exactly one → candidate ONE-RDR. More than one independent contract entangled →
   SPLIT, and NAME each contract (one line each: the fork it owns).
3. FACET OF A SIBLING? For each candidate facet-sibling, judge: are these two
   seeds facets of ONE underlying contract (same decision, different surface), or
   genuinely separate forks? Same contract → flag FACET-OF <id> (the orchestrator
   collapses; you see only this seed, do not merge). Separate → not a facet.
4. Else → ONE-RDR.

NAME THE CONTRACT (ONE-RDR / SPLIT / COLLAPSE-survivor): one paragraph — the
load-bearing decision this RDR must make ONCE, in carrier-vs-shape / identity /
format / predicate terms. This is what /rdr-seed starts from; make it a clean fork
statement, not a problem restatement.

RESEARCH BUDGET (shape only — do NOT verify source defects):
- The referenced RDR(s) under {process_rdr_dir} — is the fork already decided there?
- Prior art for the CONCEPT: ≤1 targeted query per configured corpus named in
  {rdr_resources}; cite the hit. Skip if the shape is clear without it.

OUTPUT (only this):
VERDICT: {ONE-RDR | SPLIT | COLLAPSE-CANDIDATE | DEMOTE | OUT-OF-SCOPE | LEAVE-PARKED}
REASON: one line, with the deciding RDR/contract-count cite.
FACET-OF: <id> — why  (or "none")
CONTRACT: [ONE-RDR] the named fork. [SPLIT] one named contract per line.
[if DEMOTE] WHY-NOT-RDR: the one obvious implementation.
[if OUT-OF-SCOPE] DECIDED-BY: the RDR/section that already resolved it.
```

## Phase 3 — Consolidate (orchestrator; single writer)

Holding every verdict (mirrors scope-review `§Phase 3`):

1. **Build COLLAPSE clusters** from `FACET-OF` flags + Phase-1 hints — the
   transitive group sharing one contract. This is **RDR Stage 7.1 / the
   seam-accretion tripwire applied to seeds**: K facets of one missing decision
   become one RDR.
2. **Per cluster / per seed, resolve to a terminal verdict:**
   - **COLLAPSE** → pick the survivor (richest contract statement > most
     references > age); fold each other seed's distinct fork-content into the
     survivor's Load-Bearing Contract verbatim (`folded from <id>`); the survivor
     is the `/rdr-seed <survivor>` target. Folded seeds close in Phase 4 after
     `§dependent-guard`.
   - **SPLIT** → the original seed becomes N **child seeds**, one per named
     contract (Phase 4 creates them); the original is converted (its fork is now
     carried by the children).
   - **ONE-RDR / DEMOTE / OUT-OF-SCOPE / LEAVE-PARKED** → as classified.
   - **Undecided** anything → apply the conservative bias (*Invariants*).
3. **Record** the run report at `{REPORT}` =
   `$KATA_FLIGHT_CONTEXT_ROOT/_scope-review/rdr-seed-triage-<selector-slug>.md` (same
   `_*/`-gitignored scratch location and per-selector filename rule as scope-review
   `§Phase 3`; the `--all` selector's slug is `all`). Table:
   seed × verdict × cluster × named-contract × action.

## Phase 4 — Execute verdicts (orchestrator owns all kata mutations)

`§dependent-guard` (scope-review Phase 4) runs verbatim before **any** close
(COLLAPSE-fold, OUT-OF-SCOPE). DEMOTE only strips a label, so it does not close —
but if the seed *blocks* an open kata, leave the block intact (the underlying
`type:*` kata still owns it).

- **Auto-applied (reversible; always listed in the report):**
  - **ONE-RDR** → write the named **Load-Bearing Contract** as a comment, first
    line `seed-triaged: <HEAD-sha>` (the stamp, read back like scope-review's
    `reviewed-at:`). Leave `kind:rdr-seed`. It is now a clean `/rdr-seed <id>`.
  - **COLLAPSE (survivor side)** → `kata edit <survivor> --comment` the merged
    Load-Bearing Contract + `seed-triaged: <sha>`; keep `kind:rdr-seed`.
  - **DEMOTE** → `kata label rm <id> kind:rdr-seed` (the `type:*` underneath
    re-enters it into the bug flow) + comment why-not-RDR. Reversible (re-add the
    label); auto-applied but listed prominently. Under `--confirm`, gated like a
    close (it changes which flow owns the kata).
  - **LEAVE-PARKED** → no mutation; list it under `parked:` so a human sees the
    umbrella was recognized, not silently dropped.
- **Surfaced / `--confirm` — destructive (a close, or a fan-out):**
  - **SPLIT** → for each named contract, `kata create --label kind:rdr-seed
    --related <original> --body "<contract>; split from <original> by
    rdr-seed-triage"` (carry `area:*`/`priority` from the original). Then comment
    the N child ids + `seed-triaged: <sha>` on the original and **surface** it for
    the human to close/keep — never auto-close a split parent. Under `--confirm`,
    batch the whole SPLIT for approval before creating children.
  - **COLLAPSE-fold close** → after `§dependent-guard`: `kata close <folded>
    --duplicate-of <survivor> --message "folded into <survivor> by
    rdr-seed-triage"`.
  - **OUT-OF-SCOPE close** → `kata close <id> --reason wontfix --message
    "decided-by: <rdr/section>"` (or `--superseded-by <ref>` for a specific RDR).
  - **`--confirm`** batches DEMOTE + every close + every SPLIT into one
    `AskUserQuestion` (one row/seed, recommendation pre-selected). Declining →
    keep as `kind:rdr-seed` ONE-RDR (stamp it so it doesn't re-flap).
  - **Close throttle.** Same daemon `[close.throttle]` as scope-review (>3 sibling
    closes/60s/parent) — pace closes ≥20s apart or retry serially; never disable it.

## Phase 5 — Report

```
rdr-seed-triage: <selector>  seeds: N
  one-rdr:   <id> … (contract named; ready for /rdr-seed)
  split:     <orig>→<child>+<child> … (N contracts extracted; parent surfaced)
  collapse:  <id>+<id>→<survivor> … (facets of one contract; folded in)
  demote:    <id> … (kind:rdr-seed stripped → back to bug flow)
  out-of-scope: <id>=<decided-by> …
  parked:    <id> … (umbrella/meta — recognized, left as-is)
  surfaced:  <id> … (NOT auto-acted — split parent / strand-risk / ambiguous)
  next: /rdr-seed <id>   # run per one-rdr + collapse-survivor + each split child
```

Detail lives in `{REPORT}` (gitignored).

## Pre-flight refusals

| Condition | Action |
|---|---|
| No arguments / no selector | Print Usage, stop (not a refusal — never default to the whole backlog). |
| No `kind:rdr-seed` seeds resolved | Refuse (nothing to triage). |
| `$KATA_FLIGHT_CONTEXT_ROOT/context` or `$RDR_ENV` missing | Refuse (resources/RDR-seam not found — can't ground against RDRs). |
| Selector present but resolved set empty | Refuse with message. |
| Not in a git repo | Refuse (can't read RDRs to verify the fork). |

## Failure modes

| Condition | Action |
|---|---|
| Sub-agent returns a malformed verdict | Re-brief once; if still malformed, treat as **ONE-RDR** (conservative: keep the fork, let the RDR flow refine it). Never auto-close. |
| Shape can't be settled (one-vs-split) | Conservative bias → ONE-RDR; record the tension in the contract comment. |
| Facet/collapse undecided | Do **not** merge; leave seeds separate (a wrong collapse erases a fork). |
| Close/fold would strand an open dependent | `§dependent-guard`: re-point or surface; never silently strand. |
| A seed's RDR is already authored | Phase 0 skip — Stage 1 already ran; nothing to triage. |
| `kata close` throttled | Pace ≥20s or retry serially; never disable the throttle. |

## See also

- `kata-scope-review` — **fills** the `kind:rdr-seed` bucket this skill **drains**;
  the engine it cites by reference (see *Relationship* above). Never merge them —
  the flight gate depends on scope-review staying stable.
- `kata-flow-ops --dashboard` — *observes* the seed inbox (the
  `rdr-seed:domain / :tooling` split); this skill *acts* on it. Run the dashboard
  first to see the depth, then this to drain it.
- `/rdr-seed` (`rdr/skills/rdr-seed/`) — RDR Stage 1, the
  **downstream consumer**: every surviving seed this skill produces is a clean
  `/rdr-seed <id>` input with its load-bearing contract pre-named, so Stage 1's
  shape-gate passes instead of re-deciding it.
- `rdr/stages/01-seed.md` *Two genesis pathways* — the discovered-design
  framing this skill operationalizes: a seed pile **is** the controlled
  discovered-design queue; triaging it is how 2nd-collision concepts become one
  deliberate RDR instead of N absorbed point-fixes.
