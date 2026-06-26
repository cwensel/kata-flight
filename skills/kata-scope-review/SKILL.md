---
name: kata-scope-review
argument-hint: <short-id…> | --label <name> | --parent <id> [--confirm --re-review]
description: 'Use to scope-review, consolidate, dedupe, or route katas before shipping. Mutates only the kata tracker; never code. Trigger for review/scope a kata batch, flight precheck, or $kata-scope-review.'
---

# kata-scope-review

Scope-review a batch of katas **before** they ship, so a flight only ever
resolves work that has passed a design gate. The primary goal is
**consolidation**: reduce the kata count and produce *one coherent design per
problem* by grounding each kata, merging overlapping ones, and routing
out-of-scope / rdr-shaped / un-shippable shapes out of the flight — the defects
that make `kata-flight --drain` flap (a day-plus on `marquez-import`, never
draining).

It mirrors `roborev-triage`'s architecture (orchestrator-of-parallel-grounding-
sub-agents, `$KATA_FLIGHT_CONTEXT_ROOT` resources, drop taxonomy, conservative defaults) but its
input is a **kata batch**, not roborev findings, and it runs *before* a flight,
not after a launch. Read `roborev-triage` once — this skill cites its sections
rather than restating them.

**Read-only on git.** Unlike `kata-ship`, this skill **never** creates a
worktree/branch/commit and never edits code. It *reads* source to verify claims
and mutates only the kata tracker. The `$KATA_FLIGHT_CONTEXT_ROOT` derivation is worktree-safe
(it keys off git topology), so it runs correctly from the primary checkout or a
worktree — which is why it can run any time, including mid-flight under a flight.

## Usage

```
/kata-scope-review <short-id> [<short-id> …]
/kata-scope-review --label <name>        # repeatable; OR across labels
/kata-scope-review --parent <umbrella>   # direct children of an umbrella kata
/kata-scope-review --confirm             # human-gate irreversible closes/demotes
/kata-scope-review --re-review            # re-ground already reviewed (lifecycle:reviewed) katas (§Re-review)
```

Multiple selectors → union (deduped), same as `kata-flight` Resolution. No
arguments → print this Usage. A selector present but resolving empty → refuse.

## Invariants

- **Sub-agents propose; the orchestrator disposes.** A grounding sub-agent sees
  only its own kata, so it cannot decide a dupe (two mutual dupes would each name
  the other and race). It *flags* `OVERLAPS`; Phase 3 — the only context holding
  every verdict — clusters and disposes. The orchestrator is the single writer of
  all kata mutations.
- **Consolidation merges facts; it never resolves a design fork.** Overlapping
  katas with *compatible* designs collapse-merge into one survivor (carrying every
  folded kata's edge case / test / resolved-question in verbatim — a **merge, not
  a delete**). Overlapping katas with *conflicting* approaches become
  `kind:rdr-seed` — picking between approaches is what an RDR is for; collapsing
  would silently erase a fork.
- **Never strand a dependent.** No kata is closed (out-of-scope or merge) before
  §dependent-guard re-points or surfaces any open `blocks` edge — a closed-not-
  resolved blocker freezes the dependent's `kata ready` gate forever.
- **Conservative bias = keep + escalate.** The costly error is erasing real work
  or a real fork, not leaving one extra kata open. Undecided merge → treat as
  conflict (→ rdr-seed); undecided keep-vs-close → keep + plan; undecided
  bug-vs-seed → rdr-seed; undecided survivor/parent or any strand-risk → surface,
  don't guess. (roborev-triage "when evidence can't settle it".)
- **Grounding in sub-agents.** One `general-purpose` sub-agent per kata; the
  orchestrator holds only compact verdict rows, never full kata/RDR/source text
  (roborev-triage Phase 2 discipline). Fan-out is **chunked** within the
  concurrency cap — a 68-member label is batched, not spawned all at once; log it.
- **Never drop silently.** Every kata ends in exactly one terminal verdict
  recorded in the `{REPORT}` artifact (Phase 3) and as a kata comment.

## Phase 0 — Locate & resolve

1. `$KATA_FLIGHT_CONTEXT_ROOT` + repo derivation **exactly as `roborev-triage` Phase 0 step 1**.
   **Normalize the common-dir to an absolute path first** — `git rev-parse
   --git-common-dir` returns a *relative* `.git` when run from the primary
   checkout root, and `dirname .git` → `.` silently mis-derives the roots:
   ```sh
   PRIMARY_ROOT=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")
   [ -f "$PRIMARY_ROOT/.kata-flight/env" ] && . "$PRIMARY_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$PRIMARY_ROOT")}"
[ "$(basename "$PRIMARY_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$PRIMARY_ROOT" >&2; exit 1; }
   WS=$(dirname "$PRIMARY_ROOT")   # workspace root (worktree-invariant)
   KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
   [ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
   ```
   No worktree, no branch capture — this skill mutates no git state.
2. **Resolve the batch** from selectors per `kata-flight` Resolution (explicit
   ids trusted; `--label` → `kata list --status open --json` filtered;
   `--parent` → `kata show --json` `.children[]`). Union + dedup.
3. **Skip filters** (log counts): `owner != null` (active ship), `status != open`,
   **any `kind:*`** (routed out of the bug flow — `kind:rdr-seed` awaits RDR
   authoring; `kind:rdr-tracked` waits on its in-flight RDR, named by its
   `tracks: cli/NNNN` comment), and **reviewed** (`lifecycle:reviewed`)
   **unless `--re-review`** (then route through §Re-review, not a plain skip).
4. Surface the worklist + count + skip reasons once. Empty resolved set → refuse.

## Phase 1 — Pre-dedup (orchestrator, cheap)

`kata list --status open --json` once; cluster the batch by `(area:*, title
gist, cited file)` and attach **candidate-overlap hints** to each kata's Phase-2
brief — a dedup head-start the inline KATA_PUSH check structurally cannot give.
Also pre-resolve, per kata, the shared `{slots}` the prompt needs (parent RDR
path + `deviations.md`, the RDR's tracking kata, suspect commits since the kata
was filed) so N sub-agents verify rather than re-discover.

**§seam-accretion count (the missing-design-decision tripwire).** Also count, per
candidate kata's primary code locus (`path::Symbol`, never `file:line`), how many
**already-closed** katas point-fixed that *same seam* on a *different facet* of one
behavior — `kata list --status closed --json` filtered to the shared `area:*` +
the same `path::Symbol` + "facet of / inherited from / same as" language. Attach
the count + the prior ids to the kata's Phase-2 brief. ≥2 prior point-fixes at one
seam is the signature of a *missing design decision, not a missing patch*: the
next fix should not be patched, it should be routed to an RDR (Phase 3). This is
the kata-side twin of RDR Stage 7.1 — accretion at one seam is the single-subsystem
analog of cross-RDR round-trip drift.

## Phase 2 — Ground & classify (one sub-agent per kata, parallel/chunked)

Spawn one `general-purpose` sub-agent per kata running the **§Review prompt**
(the load-bearing artifact). Each grounding sub-agent is a leaf agent per
`worktree-ship-pipeline` §leaf-agent-contract (verdict-only). It **proposes** a
verdict and makes no mutation:

| Verdict | Meaning |
|---|---|
| `IN-SCOPE` | real, contained, testable now |
| `OUT-OF-SCOPE` | superseded / rdr-adjudicated / scoped-out / unreachable / over-eng (roborev-triage drop taxonomy) |
| `RDR-SHAPED` | real design fork, contract-level, or unbounded class |
| `UMBRELLA-SPLIT` | umbrella whose DoD can't be verified from a worktree (the g65y shape) |

plus an always-emitted `OVERLAPS: <id> compatible|conflict | none` flag that
feeds Phase 3. Classification rule (contained+testable → bug; else rdr-seed) is
`roborev-triage`'s, verbatim.

### Review prompt

Fill `{…}` from Phase 0/1. Keep it terse — the directives are load-bearing
(extracted from a proven pass; provenance: `flow/rdr/RDR-KATA-SCOPE-REVIEW.md` in
the author's RDR engine, not shipped).

```text
You are scope-reviewing ONE kata in the consumer repo at {ABS_REPO}. Read-only —
do NOT modify code. Output the verdict block only. Be terse; spend tokens on
verification, not narration.

KATA {id}: {title}
CLAIM (verbatim from body): {claim}
OPEN QUESTION (if any): {open_q}

ALREADY-NAMED CONTEXT (verify, don't re-discover):
- Foundational RDR: {rdr_path}  ·  deviations: {deviations_path}
- RDR tracking kata + status: {rdr_kata}  (is the foundational work Implemented?)
- Suspect commits since the kata was filed: {commits}  (messages may already fix it)
- Candidate overlap/sibling katas: {overlap_ids}  (confirm or dismiss each)

DECIDE, in this order — stop at the first that fires:
1. SHAPE (Seed gate). Real design fork / unbounded class / contract change?
   → RDR-SHAPED. Umbrella whose DoD can't be verified from one worktree (external
   corpus, multi-kata predicate)? → UMBRELLA-SPLIT. A kata must be ONE contained,
   testable change; if it isn't, it is not flight-shippable.
2. STILL REAL? Verify the CLAIM against CURRENT source — grep the cited
   `path::Symbol` (anchor by symbol, not a rotted line number) and read the
   suspect commits; confirm the defect reproduces in code as written
   (verify against source, NOT docs, NOT the kata's own assertion). Fixed →
   OUT-OF-SCOPE(superseded). Adjudicated in {deviations_path}/RDR →
   OUT-OF-SCOPE(rdr-adjudicated). Unreachable / over-engineered → OUT-OF-SCOPE(<r>).
3. OVERLAP? For each candidate touching the SAME root cause / code site, flag
   OVERLAPS <id> and judge compatible (subset / same approach, mergeable) vs
   conflict (contradictory approach to the same problem). Do NOT decide the
   collapse — you see only this kata; the orchestrator clusters and disposes.
   Overlap does not stop you: still build the plan so a merge has it.
4. IN-SCOPE → build the plan.

RESEARCH BUDGET (only if step 2/4 needs it — do NOT exhaustively survey):
- Source/behavior: dependency source plus the consumer repository tree.
- PG semantics / standards: configured standards/docs corpus, if available.
- Prior art for the approach: configured prior-art corpora, if available.
  ≤2 targeted queries per configured corpus; cite
  the hit. If a confident verdict is reachable without a corpus, skip it.

PLAN (IN-SCOPE only — match kata cmzq's shape, source-grounded):
- Confirmed current behavior — `path::Symbol` + what the code does now.
- Open question RESOLVED (or stated + your recommendation) — source-grounded.
- Implementation plan — concrete, against named symbols; reuse existing helpers.
- Premortem (one line): assume this plan shipped and was wrong — does the verdict
  survive? If not, downgrade to RDR-SHAPED. If the plan is "do what kata/RDR 00NN
  did" (mirroring a peer's shape), check that 00NN's *constraints* transfer to
  this context, not just its shape — a locally-reasonable copy can be globally
  wrong (the contract-mirroring hazard).
- Tests — the red/green pair a later ship must satisfy.

OUTPUT (only this):
VERDICT: {IN-SCOPE | OUT-OF-SCOPE | RDR-SHAPED | UMBRELLA-SPLIT}
REASON: one line, with the deciding `path::Symbol` or RDR/deviation cite.
OVERLAPS: <id> compatible|conflict — why  (or "none")
[if IN-SCOPE] PLAN: the five-part block above.
[if OUT-OF-SCOPE] SUBREASON: superseded|rdr-adjudicated|scoped-out|unreachable|over-eng + cite.
[if RDR-SHAPED|UMBRELLA-SPLIT] WHY: the fork/predicate that can't ship as one kata.
```

**Why this shape:** the orchestrator pre-resolves `{commits}`/`{rdr_path}`/
`{deviations_path}`/`{overlap_ids}` once (shared), the decide-order short-circuits
before the corpus budget, the corpus pass is capped + skippable, and the forced
verdict block ends the agent instead of letting it spin. Front-loaded review
stays *cheaper* than the flap it prevents — one bounded verification vs. a
ship+drain+re-review cycle per bad spin-off.

## Phase 3 — Consolidate (orchestrator; single writer)

The heart of the skill. Holding every verdict:

1. **Build overlap clusters** — from the `OVERLAPS` flags + Phase-1 hints, the
   *transitive* group sharing a root cause / code site (`{zvak, cmzq}` as one
   cluster, not pairwise). This is RDR **Stage 7.1 Cluster Reconcile** for katas.
2. **Per cluster, merge vs. escalate:**
   - **Compatible** → collapse-merge. Survivor = richest state
     (`embedded-plan > comments > priority > age`) **under the RDR whose scope
     owns the consolidated design** (ambiguous parent → surface, don't guess).
     **Merge, not delete:** carry each folded kata's distinct content (edge case,
     test, *resolved open-question*) verbatim into the survivor body, tagged
     `folded from <id>`; re-ground the survivor as a unit (one plan over the whole
     cluster). Folded katas close in Phase 4 after §dependent-guard.
   - **Conflict** (contradictory approaches) → do NOT collapse; relabel the
     cluster `kind:rdr-seed` with a note naming the fork.
3. **Seam-accretion route (§seam-accretion count, Phase 1).** Independent of
   overlap: if a kata's seam already carries **≥2 closed point-fixes** on
   different facets of one behavior, route it `kind:rdr-seed` — naming the
   missing contract (the "carrier vs. shape" / "decide it once" fork), with the
   prior ids listed as the accretion trail — rather than shipping a 3rd patch.
   Catching it at patch #2 converts ~4 redundant kata cycles into one RDR. (A
   genuine one-off fix at a fresh seam still ships as a kata; the trigger is the
   *repeat count at one locus*, not the seam itself.)
4. **Record** the run report at `{REPORT}` (defined below) — a table of
   kata × verdict × cluster × evidence × action.

   `{REPORT}` = `$KATA_FLIGHT_CONTEXT_ROOT/_scope-review/<selector-slug>.md`, where
   `<selector-slug>` is the selector kebab-cased (`batch:drift-pairing` →
   `batch-drift-pairing`; an id list → the ids joined by `-`). `_*/` is
   gitignored wholesale, so the report is scratch (never committed), and the
   per-selector filename keeps **concurrent runs on different selectors from
   clobbering one report** — important because multiple sessions run this skill
   at once. Write under `$KATA_FLIGHT_CONTEXT_ROOT` (derived in Phase 0), not the cwd, so the
   path is stable whether invoked from the primary checkout or a worktree.

## Phase 4 — Execute verdicts (orchestrator owns all kata mutations)

**§dependent-guard (before ANY close).** Read top-level `.links[]` (`type=="blocks"`,
`.from`=blocker → `.to`=dependent; `.issue.links` is null — same shape kata-flight
reads). If the kata **blocks an open kata**: a merge close (folded → survivor) →
re-point the
edge — `kata edit <dependent> --remove-blocked-by <folded> --blocked-by <survivor>`
— then close the folded kata; an OUT-OF-SCOPE close that would strand an open
dependent → do **NOT** auto-close — **surface** it: `kata edit <id> --label inbox:needs-review`
(the namespaced "flag, don't close" marker) + a comment naming the
dependents whose **first line is `held-at: <YYYY-MM-DD>`** (the harness
`currentDate`, never `date`/`Date.now` — the `reviewed-at:` pattern: labels
are flat strings, so the SLA date rides the comment), and list it under
`surfaced:` in the report.

**§batch-correction (every kept-or-routed kata, orthogonal to the verdict).**
Scope-review is the **re-label authority** over `batch:*` membership — the
backstop for the producers (`kata-flight` per-kata loop step 3, `kata-ship`
`TIEBREAKER_4`) that tag a `KATA_PUSH` spin-off onto a standing selector at mint
time, `--drain` or not. Those producers tag on a *fast* fit judgment in a ship
context with no backlog view; this pass has the grounded one, so it corrects the
residual. Read the kata's current `batch:*` labels (top-level `.labels[]`) and
reconcile against the verdict:
- **Leaving the drain** — OUT-OF-SCOPE (about to close), RDR-SHAPED /
  conflict-cluster (→ `kind:rdr-seed`), or UMBRELLA-SPLIT (→ `inbox:hold`): a
  routed-out kata is no longer a flight-drainable unit, so **strip every `batch:*`**
  before/with the routing (`kata label rm <id> batch:<x>` per label) — leaving it
  would re-pull a closed/seeded/held kata into a later `--label <X>` wave. (Closing
  a kata makes its labels moot, but stripping keeps an *open* `kind:rdr-seed` /
  `inbox:hold` kata out of `batch:*` queries cleanly.)
- **Wrong batch on a kept kata** — IN-SCOPE / survivor that carries a `batch:*` it
  does **not** genuinely fit (the producer mis-tagged): `kata label rm <id>
  batch:<wrong>`, and add the correct `batch:<right>` only if one clearly applies
  (else leave it batch-less — a kept-but-unbatched kata is found by `--re-review`
  / human, not silently shipped under the wrong group).
- **Right batch** — fits the verdict: leave it; this is the common case (the
  producer's fit gate usually got it right).
Record any `batch:*` change in the kata comment + the `{REPORT}` action cell. This
is what makes "tag at mint, correct at review" safe: the funnel stays clean by
construction *and* a mis-tag is caught before it can ship.

- **Autonomous (default):** apply IN-SCOPE / OUT-OF-SCOPE (guarded) / RDR-SHAPED /
  compatible-merge / conflict→rdr-seed directly — except `UMBRELLA-SPLIT` and
  strand-risk OUT-OF-SCOPE (both surface). Run §batch-correction on every kata.
  - **IN-SCOPE / survivor:** `kata comment <id>` the plan, with a first line
    `reviewed-at: <HEAD-sha>` (the review-point stamp — labels are flat strings
    and can't carry a value, so the sha lives in the comment, read back from
    `kata show --json .comments[].body` by §Re-review). Then
    `kata label add <id> lifecycle:reviewed` (the namespaced state marker;
    see the consumer label vocabulary reference) plus `release:` / `area:` /
    `severity:` per `roborev-triage` Phase 4 rules.
  - **OUT-OF-SCOPE:** close with the real `kata close` contract — `--reason` is
    an enum (`done|wontfix|duplicate|superseded|audit-no-change`), so map the
    subreason and attach typed `--evidence`:
    - superseded (current source fixed it) → `kata close <id> --superseded-by
      <ref>` (or `--reason superseded`), `--message` naming the `path::Symbol`.
    - rdr-adjudicated / scoped-out / over-eng / unreachable → `kata close <id>
      --reason wontfix --message "<subreason>: <cite>" --evidence
      reviewed-paths:<path>`.
    - claim no longer reproduces, no code change (the `pqnf` pattern) →
      `kata close <id> --audit-no-change --message "<evidence>"`.
  - **RDR-SHAPED / conflict cluster:** `kata label add <id> kind:rdr-seed`, keep
    open, comment the fork. **If the fork's RDR already exists** (prior seed
    consumed), label `kind:rdr-tracked` + a `tracks: cli/NNNN` first-line
    comment instead — re-adding `kind:rdr-seed` re-enters the seed inbox and
    pressures a duplicate RDR (the z9ek near-miss).
  - **compatible-merge:** `kata edit <survivor> --body` (or comment) with the
    merged content, then `kata close <folded> --duplicate-of <survivor>
    --message "content folded into <survivor>"` (sugar for `--reason duplicate
    --evidence duplicate-of:`).
  - **Close throttle.** The daemon rejects >3 sibling closes by one actor under
    one parent within 60s (`[close.throttle]`). A consolidation pass closing many
    dupes/out-of-scope under one umbrella **will trip it** — space the closes
    (≥1 every ~20s under a shared parent), or close serially and tolerate the
    throttle by retrying. Do **not** disable the throttle.
- **`--confirm`:** auto-apply IN-SCOPE plan/labels + compatible-merge; batch the
  **close / demote** verdicts into one `AskUserQuestion` (one row/kata,
  recommendation pre-selected). **Declining a close is an explicit override toward
  keeping** → the kata becomes IN-SCOPE: embed the plan, add `lifecycle:reviewed` +
  the `reviewed-at:` comment line, so it never falls into limbo and re-flaps.
- **`UMBRELLA-SPLIT` always surfaces, never auto-acts** — the one exception to the
  autonomous default. Restructuring a DoD (relocate an e2e proof to the harness,
  carve a predicate into children, mark not-flight-eligible) is a judgement call
  with no safe default (`g65y` took several hand passes). In both modes: (a) tag
  `inbox:hold` so a flight won't try to ship it, (b) comment the analysis + a
  concrete proposed split, **first line `held-at: <YYYY-MM-DD>`** (the harness
  `currentDate`, never `date`/`Date.now` — same `reviewed-at:`-style stamp; a
  reaper `kata-flow-ops --reap` surfaces "held > N days" from this line, so the
  inbox ages like a queue, not a roach motel), (c) list under `umbrella:`. The
  human clears `inbox:hold` when done; the split's *children* are new katas
  entering the normal review path. Never edits the DoD, splits, or closes the umbrella.
- **Nested under `kata-flight`:** the flight orchestrator owns kata lock/label
  state and runs these mutations itself (same rule as its per-kata loop). Under
  `--confirm`, the flight surfaces the batched question. `UMBRELLA-SPLIT` and
  strand-risk surfaces are **never a blocking stop** — tag/drop from the ship
  queue and continue; the human handles them out-of-band.

## Phase 5 — Report

```
scope-review: <selector>  reviewed: N  [re-review: tier0=<n> tier1=<n> tier2=<n>]
  in-scope:   <id> … (lifecycle:reviewed, plan embedded)
  merged:     <id>+<id>→<survivor> … (cluster collapsed; folded content carried in)
  out-of-scope: <id>=<reason> …
  rdr-shaped: <id> … (→ kind:rdr-seed; ‡ = conflicting-design cluster)
  umbrella:   <id> … (inbox:hold; split needed: <one-line>)
  surfaced:   <id> … (NOT auto-acted — strand-risk close / ambiguous parent; needs you)
  next: /kata-flight --label <X>   # ships only the in-scope + survivor set (review gate runs by default)
```

Detail lives in `{REPORT}` (`$KATA_FLIGHT_CONTEXT_ROOT/_scope-review/<selector-slug>.md`, gitignored).

## Re-review cascade (`--re-review`)

A first review knows nothing → it always runs the full §Review prompt. A
re-review asks the *narrower* question — *the world moved (RDRs landed); does my
prior verdict still hold?* — so it is a **delta check** (the RDR flow's Propose
Stage-0 freshness check). `--re-review` re-grounds only the reviewed set
(`lifecycle:reviewed`); OUT-OF-SCOPE (closed/out-of-batch) and
`kind:rdr-seed` (skip-filtered) stay as
routed unless a human reopens them. Cost scales with what changed, via three
tiers — each kata enters at Tier 0 and escalates only on detected drift:

- **Tier 0 (orchestrator, no sub-agent).** Read `<reviewed-at>` from the
  `reviewed-at:` line of the kata's scope-review comment (`kata show --json
  .comments[].body`) and the cited file paths from its embedded plan; if
  `git log <reviewed-at>..HEAD --oneline -- <files>` is empty **and** the parent
  RDR's tracking-kata status is unchanged → **auto-confirm** (append a fresh
  `reviewed-at: <HEAD>` comment line, log `confirmed (tier-0)`). A kata
  **reopened since its stamp** never Tier-0 auto-confirms — its stamp is stale by
  construction → automatic Tier-1.
- **No `reviewed-at:` line.** A `lifecycle:reviewed` kata with no `reviewed-at:`
  stamp has no sha to diff from → Tier 0 cannot run → **automatic Tier-1**
  (self-healing: the pass writes a real `reviewed-at: <HEAD>` stamp, so the
  *next* `--re-review` gets cheap Tier-0).
- **Tier 1 (freshness-delta sub-agent — no corpus, no plan rebuild).** Brief =
  the kata's prior verdict + embedded plan + the bounded delta the orchestrator
  computed (`commits since reviewed-at touching cited files`, RDR status delta,
  new deviations, new candidate-overlap katas). Three checks: (1) do the cited
  `path::Symbol`s still show the defect? (2) did any named RDR/deviation now adjudicate
  it? (3) did a new kata appear that overlaps it? All "nothing moved" → CONFIRM
  (re-stamp). Any drift it can't cheaply resolve → ESCALATE.
- **Tier 2.** The full §Review prompt, run only on escalations + first-ever
  reviews.

**Safe by construction:** the light tiers only *confirm-or-escalate* — they never
*decide* a disposition change. Real drift routes to the full prompt, which makes
the call. No silent staleness.

## Pre-flight refusals

| Condition | Action |
|---|---|
| No arguments | Print Usage, stop (not a refusal). |
| `$KATA_FLIGHT_CONTEXT_ROOT missing / wrong consumer repo | Refuse (resources/repo not found). |
| Selector present but **initial** resolved set empty | Refuse with message. |
| Not in a git repo | Refuse (can't read source to verify claims). |

## Failure modes

| Condition | Action |
|---|---|
| Sub-agent returns a malformed verdict | Re-brief once; if still malformed, treat as RDR-SHAPED with an `## Open question` (keep + escalate). Never ask the user (unless `--confirm`). |
| Evidence can't settle a kata | Apply the conservative bias (keep + escalate); record the tension in the comment. |
| Overlap compatibility undecided | Treat as **conflict** → `kind:rdr-seed` (never silently merge). |
| Close would strand an open dependent | Re-point (merge) or surface (out-of-scope); never silently strand. |
| Ambiguous survivor / parent RDR for a cluster | Surface; don't guess. |
| Kata reopened since its `reviewed-at` stamp | Force Tier-1 in `--re-review`; never Tier-0 auto-confirm. |
| `lifecycle:reviewed` kata with no `reviewed-at:` | Can't Tier-0 (no sha) → Tier-1; the pass writes a real stamp (self-healing). |
| `kata close` throttled (>3 sibling closes/60s/parent) | Space closes (~20s apart) or retry serially; never disable the throttle. |
| Many closes in one consolidation pass | Expected under an umbrella — pace them; the throttle is a feature, not an error. |
| Invoked under a lock-owning parent (kata-flight) | Parent owns mutations; surface UMBRELLA-SPLIT / strand-risk non-blocking. |
| Routed-out kata still carries `batch:*` | §batch-correction strips it (a closed/seeded/held kata is no longer flight-drainable). |
| Kept kata carries a `batch:*` it doesn't fit | §batch-correction removes the wrong one; add the right one only if one clearly applies, else leave batch-less. |

## See also

- `roborev-triage` — same architecture, post-launch finding triage; this skill
  cites its Phase-0 derivation, Phase-2 grounding discipline, drop taxonomy, and
  Phase-4 label rules.
- `kata-flight` — its review gate (default-on, suppressed by `--no-review`)
  front-loads this skill at the head of every wave (incl. `--drain` re-sweeps),
  so spin-offs pass the same gate before they can ship. Its per-kata loop step 3
  tags `KATA_PUSH` spin-offs onto standing
  selectors at mint time (`--drain` or not); this skill's §batch-correction is the
  paired backstop that strips/corrects that membership when grounding reclassifies
  the kata.
- `kata-ship` TIEBREAKER_4 — the inline §spinoff-worthiness check this skill
  replaces with a backlog-aware, corpus-grounded, up-front pass. Its spin-offs
  carry `src:`/`severity:` provenance + (under a flight) a `batch:*` thread;
  §batch-correction reconciles that thread against the grounded verdict.
- `rdr-seed-triage` — the **downstream** consumer of this skill's `kind:rdr-seed`
  output. This skill *fills* the seed bucket (a terminal verdict, then skip-filters
  it); `rdr-seed-triage` *drains* it in an independent session — deciding, per
  seed, one-RDR / split / collapse / demote / out-of-scope before `/rdr-seed`. It
  reuses this skill's Phase-0 derivation, `§Phase 2` grounding, `§seam-accretion
  count`, `§dependent-guard`, and `{REPORT}` convention by reference. Two ends of
  one pipe — keep them separate.
- Design provenance (author's RDR engine, not shipped):
  `flow/rdr/RDR-KATA-SCOPE-REVIEW.md`. This skill is the source of truth.
