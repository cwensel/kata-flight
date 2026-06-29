---
name: roborev-triage
argument-hint: <RDR_PATH...> [--batch-label <key>]
description: 'Use after an RDR implementation launch leaves open roborev findings. Single-pass unattended triage routes findings to drop, fix-now, kata-bug, or rdr-seed, grounded against one or more coupled RDRs. Trigger for roborev triage after launch.'
---

# roborev-triage

Single-pass, **unattended** triage of the roborev findings left after an
RDR implementation launch. Replaces `/roborev-refine` after launch.
Accepts either one RDR or an ordered coupled set implemented in the same
branch; in a coupled run every finding is grounded against the full set,
not only the first RDR.

Two design choices, each fixing a flap cause: (1) **no loop** — the refine
loop is the flap engine (a moving `merge-base..HEAD` range re-flags main's
own merged fixes), so triage reads immutable per-commit diffs once; (2)
**ground each finding** against the RDR set + `{RDR_RESOURCES}` that roborev's
repo-sandboxed prompt never sees (else it reverses RDR-adjudicated
decisions, re-raises scoped-out work, or rates severity by code shape not
reachability). Every finding's fate is decided from evidence; anything
unsettled is filed into a kata and surfaced when that kata ships — the run
never stops to ask.

## Usage

```
/roborev-triage <RDR_PATH>                         # e.g. cli/0037-materialize-policy.md
/roborev-triage <RDR1> <RDR2> [<RDR3>...]          # coupled implementation
/roborev-triage <RDR_PATH...> --batch-label <key>  # caller-supplied batch key (e.g. rdr-implement-triage)
```

`<RDR_PATH...>` is the required ordered input. The first path is primary;
the remaining paths are companions. Derived:

- `<art>` = the directory beside the primary RDR named after its basename
  without `.md` (launch.md's rule); holds `req-list.md`, `deviations.md`,
  `status.md`, `coverage.md`, `verification.md`, and `triage.md`.
- `COMPANION_ART_DIRS` = each companion RDR's artifact directory by the
  same rule. Grounding sub-agents read companion `req-list.md`,
  `deviations.md`, `coverage.md`, and `verification.md` when present.
- `BATCH_LABEL` = `--batch-label <key>` if given, else
  `batch:roborev-<YYYYMMDD>` (Phase 0 step 4; namespaced per
  the consumer label vocabulary reference). A caller that drives
  triage per run (notably `/rdr-implement-triage`, which passes
  `batch:rdr-<NNNN>` for one RDR or a coupled key such as
  `batch:rdr-0081-0092`) supplies a key unique to that run so a later
  `/kata-flight --label <key> --drain` re-sweeps **only** that run's
  children — the dated default collides across same-day runs. The key
  replaces the dated label; the `roborev` source label is always added
  too, so provenance is never lost.
- `{RDR_RESOURCES}` = `$KATA_FLIGHT_CONTEXT_ROOT/context/rdr-resources.md` — the evidence
  index (corpora + design-doc anchors) the spec was grounded against.
  It's now tracked in the configured Kata Flight context root; a worktree has no `_rdr/`,
  so read it from `$KATA_FLIGHT_CONTEXT_ROOT` (not `$PRIMARY_ROOT`). `$KATA_FLIGHT_CONTEXT_ROOT` is the
  primary checkout's sibling, derived in Phase 0 step 1 — symlink-safe
  because it keys off the worktree's git topology. This is the project evidence
  root, not the Kata Flight skill checkout or the external RDR methodology repo.

## Invariants

- **Unattended — never blocks on the user.** No `AskUserQuestion`, ever.
  A finding the evidence can't settle is filed as a kata with an
  `## Open question` section; the decision is taken when that kata ships.
- **One pass, frozen world.** `BASE` and `HEAD` are captured once
  (Phase 0); every phase reasons against that snapshot. The skill never
  invokes `/roborev-refine`. The only review past `HEAD` is the
  per-commit auto-review of a FIX-NOW commit, swept exactly once and
  never re-fixed — bounded, not a loop.
- **Per-commit reviews are the spine.** A commit's diff is immutable, so
  a per-commit finding can't flap. The single `--since BASE` range review
  is an additive cross-commit net, not the primary feed.
- **Never drop silently.** Every finding ends in exactly one terminal
  state in `<art>/triage.md` and is closed via `/roborev-respond` — DROP
  cites the reason; kata-bug/rdr-seed cites the kata short_id.
- **Grounding in sub-agents.** The orchestrator holds only the compact
  finding rows + verdicts + paths — never full review text, RDR text, or
  source (launch.md's orchestrator-of-sub-agents discipline).

## Phase 0 — Locate & freeze (orchestrator; cheap reads)

1. `git rev-parse --git-common-dir` + `--show-toplevel`: note worktree vs
   primary checkout and branch. Either is fine. Set
   `PRIMARY_ROOT=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")`
   — the primary checkout, the sibling of the configured context root that holds the
   consolidated resources (read `{RDR_RESOURCES}` and
   `project-guidelines.md` from the configured context root). Assert the
   intended repo, else a leaked `cd` into a sibling froze the wrong
   `BASE`/`HEAD`:
   `[ -f "$PRIMARY_ROOT/.kata-flight/env" ] && . "$PRIMARY_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$PRIMARY_ROOT")}"
[ "$(basename "$PRIMARY_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$PRIMARY_ROOT" >&2; exit 1; }`
   Then resolve the consolidated-resources root from the workspace marker
   (tracked, sibling of the primary checkout) and assert it exists:
   `WS=$(dirname "$PRIMARY_ROOT")   # workspace root (worktree-invariant)`
   `KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
   `[ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }`
2. Freeze once: `HEAD=$(git rev-parse HEAD)`,
   `BASE=$(git merge-base main HEAD)`.
3. Read only the header of every available `<art>/status.md` (primary and
   companions; match the `COMPLETE` token anywhere in the line, not only
   leading — it may be a `# Status … COMPLETE` heading). No `COMPLETE`
   token or missing → proceed, flag in the report (advisory only; never a
   refusal). In coupled mode, the primary status is authoritative for the
   shared launch; companion status files are advisory if absent.
4. Resolve `BATCH_LABEL` (the `kata-flight` handoff key): the
   `--batch-label <key>` value if the caller passed one, else
   `batch:roborev-<YYYYMMDD>` from the harness `currentDate` (never
   `date`/`Date.now`).

## Phase 1 — Collect & reconcile (orchestrator; deterministic, no judgement)

1. **Spine.** `roborev fix --open --list --all-branches` (`--all-branches`
   required — worktree/kata branch names differ from the current branch).
   Parse each `Job #N` block for `Git Ref`, `Branch`, `Subject`,
   severity. Keep jobs whose ref is an ancestor of `HEAD`
   (`git merge-base --is-ancestor <ref> HEAD`; exit 0 = in window). For
   each, `roborev show --job N --json` → parse the `output` field (it is
   markdown, **not** a `findings[]` array): split on `---`, read each
   finding's `**Severity**` / `**Location**` / `**Problem**` / `**Fix**`.
2. **Cross-commit net.** `roborev review --since "$BASE" --wait` — **once**;
   surfaces only defects that emerge from commit interaction. Dedup
   against the spine by `(source-anchor, problem-gist)`, charging duplicates
   to the per-commit job so the close path is unambiguous. Never re-run;
   if it touches files outside `git log $BASE..HEAD --name-only`, treat
   those as candidate-churn in step 3.
3. **Staleness (confirm-at-HEAD).** Mark `candidate-superseded` when a
   later commit may have resolved it (`git log <ref>..HEAD --oneline --
   <file>` non-empty, or the cited symbol/behavior no longer matches current
   source). Phase 2 confirms → DROP `superseded-at-HEAD`. This absorbs
   fix-then-revert churn (guard added by commit N, removed by N+1).

Result: one compact row per finding —
`{job_id, ref, location_hint, stable_anchor?, severity, problem, fix, candidate_superseded}`.

## Phase 2 — Ground & classify (one sub-agent per finding, in parallel)

Spawn one `general-purpose` sub-agent per finding (collapse exact
duplicates first). These are **leaves** per `worktree-ship-pipeline`
§leaf-agent-contract — they ground + classify and return a verdict only,
never spawning further agents. Self-contained brief (≤200 words), no
shared context:

- The finding row.
- `RDR_PATHS`, `<art>/deviations.md`, `<art>/req-list.md`, and any
  companion artifact files (the launch's own adjudications + REQ quotes).
- `{RDR_RESOURCES}` (absolute `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...` — the worktree
  has no `_rdr/`, so read from `$KATA_FLIGHT_CONTEXT_ROOT`) — the grounding roborev
  lacked. Search via
  the project-configured search tools or local documentation; `docs/principles.md` is default-load.
- The absolute repo/worktree path (so reads/searches resolve).
- The classification rule + verdict contract below.

The sub-agent **ultrathinks** and returns exactly one verdict:

- **DROP** + sub-reason, each citing its evidence:
  `superseded-at-HEAD` (current source no longer exhibits it) ·
  `rdr-adjudicated` (RDR/`deviations.md` already decided this — cite the
  section; the finding reverses a documented decision) ·
  `project-scoped-out` (a standing decision excludes it, e.g.
  no-live-DB — cite it) · `unreachable` (threat model shows no live path
  — cite the guarding invariant) · `over-engineering` (defense-in-depth
  for a hypothetical — cite `docs/principles.md`).
- **FIX-NOW** — contained, unambiguous, data-safety/security, clearly
  in-this-RDR-set's scope, cheap. Deliberately narrow. If the fix proves
  non-trivial mid-edit, it **downgrades to KATA-BUG** rather than ask.
- **KATA-BUG** — a contained, testable defect (red/green pair writable),
  in project scope but out of this RDR's scope or deferred. Returns
  `title`, `body`, `area`, `severity`, `priority`, threat model,
  one-line course-of-action.
- **RDR-SEED** — the real fix is architectural, changes a contract, or
  spans an unbounded class the RDR must adjudicate (e.g. "use a generic
  AST walker", "redesign the bind path"). No red/green pair. Returns the
  seed framing + why it's not a bug.

**Classification rule.** Contained + testable now → KATA-BUG; otherwise
(architectural / contract-level / unbounded-class) → RDR-SEED. This sets
the downstream path: `type:bug` ships via `kata-flight`; `kind:rdr-seed` is
refused by kata-ship gate 4 and routes to RDR authoring.

**When the evidence can't settle it (no user stop).** Apply conservative
defaults and bake the open question into the kata body, never DROP it:
- undecided bug-vs-seed → file **RDR-SEED** (forces human design
  attention; won't auto-ship as a mechanical fix);
- undecided severity/priority → file as the **higher** severity;
- undecided drop-vs-file → **file** (dropping needs positive evidence).
Add an `## Open question` section stating the tension + the sub-agent's
recommendation, so the shipping run (kata-ship/kata-flight) resolves it.

Every verdict carries its **grounding evidence** verbatim so the kata is
self-contained.

## Phase 3 — Consolidate (orchestrator)

1. **Collapse** same-root-cause findings into one kata (e.g. five
   adjacent uncovered-AST-shape findings → one generic-walker rdr-seed).
   Record all originating job ids so each gets closed in Phase 4.
2. **Record** `<art>/triage.md`: a table of finding × verdict × evidence
   × outcome (`kata <short_id>` | `drop:<reason>` | `fix-now:<sha>`).
   The final report is derived from it.

## Phase 4 — Execute verdicts (orchestrator owns all mutations)

- **DROP:** `/roborev-respond` the job, citing the sub-reason + evidence;
  close.
- **FIX-NOW:** apply the minimal change in the current checkout (or via a
  single fixer sub-agent) and **commit it** (so the branch is clean
  before ff-merge and the edit is captured), then `/roborev-respond` the
  original job citing the fix commit; close. The fix-commit triggers a
  fresh per-commit auto-review — an immutable single-commit review, so it
  can't flap. Collect those fix-commit reviews **once** at the end of
  Phase 4 and run them through Phase 2 grounding (they are in-window
  past the frozen `HEAD`). A fix-commit review whose only finding is
  another FIX-NOW is **filed as KATA-BUG, not re-fixed** — the
  fix-then-review sweep is bounded to one round, never a loop.
- **KATA-BUG / RDR-SEED:**
  1. `kata search "<gist>"` + `kata list --status open --json` for an
     existing home; attach rather than duplicate if one fits.
  2. Else `kata create "<title>" --body-file -` with a self-contained
     body: **Problem**, **Threat model / reachability**, **Grounding**
     (RDR section + corpus/invariant evidence), **Course of action**, and
     **Open question** when Phase 2 left one.
  3. Labels (namespaced — see the consumer label vocabulary reference):
     `src:roborev` (provenance), `<BATCH_LABEL>`
     (Phase 0 step 4 — a `batch:*` key: the RDR-scoped key under a caller
     override, else the dated default), `area:<x>`,
     `severity:<low|medium|high>`, `type:bug` **or** `kind:rdr-seed`,
     and the release scope `release:v1.0` **or**
     `release:post-1.0` (never bare `v1.0`, which means *shipped*).
     A ship-ready `type:bug` is also stamped `lifecycle:queued` (triage
     deems it drainable; `lifecycle:*` is single-valued — this *is* its
     state, no prior `filed` to replace); a `kind:rdr-seed` gets **no**
     `lifecycle:*` (it exits to RDR authoring, not the drain).
     `--related <RDR ref>` for every input RDR materially implicated by
     the finding; if unsure in a coupled run, relate it to all `RDR_PATHS`.
     Set `--priority` whenever you set a
     `severity:` label, per the `severity:` → priority table in
     the consumer label vocabulary reference (severity × reachability;
     0 = highest; reserve 0–1 for live data-safety/security).
  4. `/roborev-respond` the originating job(s) — including collapsed ones
     — citing the kata short_id; close.
- **Nested context.** If invoked under a parent that owns kata
  lock/label commands (a ship pipeline), do **not** run `kata
  create`/`kata label`; emit a `KATA_PUSH:` packet (target = short_id |
  `new`; proposed title/body; severity + source-anchor; one-sentence
  rationale; `batch = <BATCH_LABEL>` so the parent applies the same
  key) and let the parent file it — mirroring `/roborev-refine`
  §3a-bis and kata-ship's TIEBREAKER_4. (Handoff, not a user stop.)

## Phase 5 — Report

```
triage: <RDR_PATH...> @ <HEAD short>  (base <BASE short>)  batch: <BATCH_LABEL>
  findings: <total>  (spine <n>  range-net <m>  deduped <d>)
  dropped:  <count>  superseded=<n> rdr-adjudicated=<n> scoped-out=<n> unreachable=<n> over-eng=<n>
  fixed-now: <id>=<sha> …       (committed inline; ↳<short_id> = fix-commit review filed a follow-up)
  kata-bug:  <short_id> …    (★ = has open question)
  rdr-seed:  <short_id> …    (★ = has open question)
  next: /kata-flight --label <BATCH_LABEL>   # ships the bug children
        (the standing queue is `kata ready --label lifecycle:queued`;
         rdr-seed children route to RDR authoring; kata-ship gate 4 refuses them)
```

Detail lives in `<art>/triage.md`. Leave the worktree/branch intact for
the merge/ship flow.

## Failure modes

| Condition | Action |
|---|---|
| Not in a git repo / `git merge-base main HEAD` fails | Refuse; surface (cannot freeze a window). |
| `roborev status` not healthy | Refuse; surface the normal command output. Do **not** run `roborev daemon ...`. |
| `<art>/status.md` not COMPLETE / missing | Proceed; flag in report. |
| No in-window jobs AND range review clean | Report "nothing to triage"; exit. |
| Range review touches out-of-window files | Treat as candidate-churn (Phase 1.3); do **not** re-run. |
| Job ref not an ancestor of HEAD | Out of window; skip + log. |
| Sub-agent returns a malformed verdict | Re-brief once; if still malformed, file RDR-SEED with an `## Open question`. Never ask the user. |
| Evidence can't settle a finding | Apply Phase 2 conservative defaults + `## Open question`; never DROP, never ask. |
| Existing kata fits a finding | Attach (label + comment); don't duplicate. |
| Invoked under a lock-owning parent | Emit `KATA_PUSH:` packets; don't run kata create/label. |

## See also

- The implementation launch prompt
  (`rdr/prompts/implementation/launch.md`) — runs before this;
  ends at its COMPLETION GATE and never runs roborev.
- `/roborev-respond` — the close path for every terminal finding.
- `/kata-flight` — ships the `<BATCH_LABEL>` `bug` children (the
  dated default, or the caller-supplied RDR-scoped key); its ship run
  is where any baked-in open question reaches the user.
- `{RDR_RESOURCES}` (`$KATA_FLIGHT_CONTEXT_ROOT/context/rdr-resources.md`) — the
  evidence index the Phase-2 sub-agents ground against.
