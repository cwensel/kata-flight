---
name: rdr-implement-triage
argument-hint: <RDR_PATH...> [@<prompt-path>] [--ship | --close-and-flight] | --resume <RDR_PATH...>
description: 'Use to run unattended RDR Stage 8 implementation for one or more coupled RDRs plus roborev triage in one worktree session. Optional flags also ship, close the RDR tracker(s), and flight follow-up katas. Trigger for implement RDR with triage.'
---

# rdr-implement-triage

The unattended, triage-chaining **wrapper around `/rdr-implement`** (RDR
Stage 8). Runs one locked RDR, or a coupled set of locked RDRs that must
be implemented together, as a single **walk-away** session: invoke it,
leave the terminal, return to a completed implementation on one isolated
branch with its roborev findings triaged into kata — left UNMERGED for you
to ship.

Relation to `/rdr-implement`: both dispatch into the same launch.md
orchestrator (Stage 8). `/rdr-implement` is the **attended** path —
it stops for a genuine author decision and ends at the green branch with no
roborev step. This skill is the **unattended** path — it records author
decisions as deviations and continues, then chains `/roborev-triage` on the
COMPLETE branch. Same implementation phase, with triage bolted on and no
human in the loop.

**Coupled RDRs are first-class.** If two or more `<RDR_PATH>` arguments are
given, the first is the **primary** RDR and the rest are companions. The
run creates exactly one worktree, one branch, one implementation commit
stream, one roborev triage pass, and one optional ship. The launch and
triage briefs carry the full ordered RDR list; every phase treats the
combined REQ set as the implementation surface, not as independent serial
runs. Never silently drop companion RDRs by running only the first path.

**Flat — the parent is the orchestrator.** It creates the worktree, then
plays launch.md's orchestrator role directly, spawning each phase sub-agent
**from the top level** where the Agent tool works. It does **not** wrap the
launch in a single sub-agent — that sub-agent couldn't spawn the phase
children launch.md needs (the nested-agent wall that stalled earlier runs).
Worktree isolation still lets another Claude session ship kata concurrently.
(Operative rules in Invariants below.)

Consumer of `worktree-ship-pipeline` — **read that first.** Cites its
isolation anchors (`§worktree-invariant`, `§scope-discipline`,
`§phase-1b-worktree-creation`, `§preflight-shared`,
`§worktree-isolation-gate`, `§resume-mechanics`) and
`§context-discipline`'s report-budget + brief rules. **Two divergences:**
(1) `§context-discipline`'s "skills run inside agents, never by parent"
does **not** hold — the parent runs launch.md's orchestrator role and
`/roborev-triage` directly, so their sub-agents dispatch from the top
level; (2) no rebase/refine/merge — it stops before merge, triage in their
place. The parent still reads only summaries and never `cd`s in except the
bounded Phase-2 triage step.

## Usage

```
/rdr-implement-triage <RDR_PATH>                         # paste the launch prompt below the command
/rdr-implement-triage <RDR_PATH> @<PROMPT_PATH>          # or read it from a file
/rdr-implement-triage <RDR1> <RDR2> [<RDR3>...]          # coupled implementation in one branch
/rdr-implement-triage <RDR_PATH...> --ship               # build+triage, then land the branch to main (no docs/kata/flight)
/rdr-implement-triage <RDR_PATH...> --close-and-flight   # …and flip RDR+indexes, close tracker(s), flight bug children
/rdr-implement-triage --resume <RDR_PATH...>
```

**Landing flags (both default OFF — bare behavior is unchanged).** They
only fire on a clean `complete` launch + `ok` triage; any earlier
`stopped:*`/`incomplete:*` halts before them exactly as today, leaving
the branch unmerged.

- **`--ship`** — after triage, run `lib-land-rdr §land-ship`
  (rebase-if-moved → `go test && golangci-lint` → squash → ff-merge →
  teardown). A green rebased tip is the only gate; a triage fix-now
  commit ships if green.
- **`--close-and-flight`** (implies `--ship`) — then run
  `§land-rdr-docs` (one `docs(rdr)` commit on `the configured RDR docs branch`:
  Status→Implemented + README row + conditional matrix), `§land-kata-close`
  (close the `kind:rdr-tracked` tracker with typed evidence), and
  `§land-flight` (`/kata-flight --label <BATCH_LABEL> --drain` at top
  level, output to `<ART_DIR>/flight.md`, digest only).

The ladder: bare (build+triage, stop on branch) → `--ship` (… + land to
main) → `--close-and-flight` (… + flip/close/flight). These reuse the
**warm orchestrator** (RDR number, `BATCH_LABEL`, `<art>`, and
`merged_sha` already in context), so nothing is re-derived from disk —
that is the token/wall-clock win over invoking `/rdr-implement-land`
separately. (The standalone `/rdr-implement-land` exists for landing a
branch from a *cold* start, e.g. after the attended `/rdr-implement`.)

- `<RDR_PATH...>` — one locked RDR, or an ordered coupled set, e.g.
  `cli/0081-foo.md cli/0092-bar.md`. The first path is primary and names
  shared artifacts; companions are not optional context.
- **Launch prompt** `LAUNCH_PROMPT` — a path by default; precedence: inline
  body > `@<PROMPT_PATH>` > engine default.
  - **Default:** `/rdr-implement --launch-prompt-path` (the engine owns where
    its prompt lives; this skill never reconstructs `rdr/`'s layout).
  - **`@<PROMPT_PATH>`** overrides it. Either path is threaded into the phase
    briefs — the parent never reads the body (it stays out of the long-lived
    orchestrator context; each phase agent Reads the path itself).
  - **Inline body** overrides both — freezes it into the session against the
    file moving mid-run, at the cost of the body in orchestrator context.

Derived: `RDR_PATHS` = ordered input list; `PRIMARY_RDR_PATH` = first
entry; `NNNN_LIST` = each 4-digit RDR number; `SLUG` = primary RDR basename
without `.md`; `<art>` = the directory beside the primary RDR named `SLUG`
(launch.md's rule); `COMPANION_ART_DIRS` = companion artifact dirs by the
same rule; `{RDR_RESOURCES}` =
`<KATA_FLIGHT_CONTEXT_ROOT>/context/rdr-resources.md` (absolute — see pre-flight gate 1;
the worktree has no `_rdr/`, so resources live in the configured Kata Flight context root
repo); `SHORT_ID` = `rdr-<NNNN>` for one RDR, `rdr-<NNNN>-<MMMM>` for two
RDRs, and `rdr-<first>-plus<N>` for three or more; `BATCH_LABEL` =
`batch:<SHORT_ID>` (namespaced per the consumer label vocabulary
reference) — the run-scoped key every kata this run files carries, so a
later `/kata-flight --label <BATCH_LABEL> --drain` re-sweeps **only** this
implementation's children. Single-RDR labels remain `batch:rdr-<NNNN>`.

## Parameters (consumed by worktree-ship-pipeline isolation anchors)

| Parameter | Value |
|---|---|
| `WORK_SOURCE` | `LAUNCH_PROMPT` (engine path from `/rdr-implement --launch-prompt-path`, or `@<PROMPT_PATH>`, or an inline body) run against ordered `RDR_PATHS` |
| `SHORT_ID` | `rdr-<NNNN>` for one RDR; `rdr-<NNNN>-<MMMM>` for two; `rdr-<first>-plus<N>` for three or more |
| `BRANCH` | `worktree-<SHORT_ID>` |
| `WORKTREE_PATH` | `.claude/worktrees/<SHORT_ID>` |
| `TARGET_BRANCH` | `$(git branch --show-current)` captured at preflight |
| `LOCK_ANCHOR` | none — RDRs have no tracker lock; the worktree branch *is* the lock |
| `CLOSE_STEP` | none — this skill never merges or closes anything |

## Invariants

- **Never blocks on the user.** No `AskUserQuestion`, ever — and no
  free-text "how should I proceed?" checkpoint either. Each step is
  **pass → continue** or **fail → refuse with a named reason and halt**;
  there is no third "ask" branch. Never pause at a phase boundary, never
  ask permission to advance, never present a menu. A passing gate is
  silent — proceed to the next step without announcing it. A decision the
  evidence can't settle is recorded (launch → `deviations.md`; triage →
  kata `## Open question`) and the run continues. (Mirrors launch.md's
  escalation rule: a precondition failure is a halt, not a question.)
- **Parent IS the orchestrator (flat).** The parent plays launch.md's
  orchestrator role directly — cheap prechecks itself, phase sub-agents
  spawned from the top level (a wrapping launch sub-agent can't fan them
  out: no Agent tool one level down). This is the **orchestrator** side of
  `worktree-ship-pipeline` §leaf-agent-contract — the orchestrator stays
  top-level and can't itself be an agent; only its phase/triage leaves run
  as sub-agents. It holds only paths + ≤200-word
  summaries; only the phase/triage sub-agents `cd` in and pass the
  `§worktree-isolation-gate`. The parent creates the worktree with a raw
  Bash `git worktree add` (no `EnterWorktree` — see
  §phase-1b-worktree-creation §worktree-creation-rationale) and never
  `cd`s into it: Phase-2 triage delegates to `/roborev-triage`, whose own
  sub-agents `cd` in.
- **Build phases never touch main; never merge; never tear down.** Phases
  1–2 (launch + triage) leave the worktree + branch intact and UNMERGED.
  The ff-merge + teardown happen **only** in Phase 3 under `--ship` /
  `--close-and-flight` (via `lib-land-rdr §land-ship`); without a landing
  flag the end-state is unchanged — branch intact, UNMERGED.
- **Launch prompt is supplied data, never hardcoded.** Inline-pasted
  (preferred) or read from a path at runtime. The RDR docs repo gains no
  dependency on the consumer repository tooling.
- **Triage only on COMPLETE.** A halted launch is not triaged.
- **Coupled means atomic.** For multi-RDR input, do not create one worktree
  per RDR and do not implement them serially. Any launch blocker halts the
  coupled run; triage, ship, docs, tracker close, and flight all see the
  same combined branch and `BATCH_LABEL`.

## Flow (runs start-to-finish without pausing)

`Pre-flight → Phase 1b (worktree) → Phase 1 (parent orchestrates launch.md
phases) → Phase 1 gate → Phase 2 (parent runs /roborev-triage) → Phase 2
gate → [Phase 3 §land-ship — only with --ship/--close-and-flight] →
[Phase 4 §land-rdr-docs + §land-kata-close + §land-flight — only with
--close-and-flight] → Final report`. The parent advances through
these automatically. Without a landing flag the flow ends at the Phase 2
gate exactly as before (branch left UNMERGED). The only interruptions are a **named `stopped:*`
halt** (a failing gate) or the **terminal report**. There is no
"proceeding?" prompt at any boundary. If you ever find yourself about to
emit a menu or a "how should I proceed" question with no failing gate to
name, that is the bug this skill exists to prevent — continue instead.

## Pre-flight (parent; read-only)

Pass/refuse only — **no ask branch.** Run all gates; if every one passes,
proceed **directly and silently** to Phase 1b (do not summarize results,
do not ask whether to continue, do not present a menu). If any gate fails,
halt with its named `stopped:<reason>` — that halt is the *only* stop, and
it names the specific failing gate (never a generic "checks rejected").

Per `§preflight-shared` (gate 0 §repo-anchor first), plus RDR gating:

0. **§repo-anchor.** `REPO_ROOT="$(git rev-parse --show-toplevel)"`;
   refuse `stopped:wrong-repo` unless it matches the configured consumer repo. A
   leaked `cd` into a sibling (e.g. `process` on `the configured RDR docs branch`) would
   otherwise pass gate 1 and create the worktree in the wrong repo.
   Re-assert before worktree creation (Phase 1b).
1. `git -C "$REPO_ROOT" branch --show-current` non-empty;
   `git -C "$REPO_ROOT" status --porcelain` clean. Capture
   `TARGET_BRANCH`, set `PRIMARY_ROOT="$REPO_ROOT"`, emit the
   §repo-anchor divergence advisory. Then resolve `KATA_FLIGHT_CONTEXT_ROOT` from the
   workspace marker — the consolidated resources (`context/`,
   `rdr/evidence/`), tracked — and refuse if absent. **Fast path:** if the
   session carries an `RDR seam pre-resolved` block (the consumer-repo
   `SessionStart` hook emits one), take `KATA_FLIGHT_CONTEXT_ROOT` from it as a literal —
   skip the shell below. Otherwise resolve it in one call:
   ```sh
   WS="$(dirname "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")"   # workspace root (worktree-invariant)
   KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
   if   [ -f "$PRIMARY_ROOT/.kata-flight/workspace" ]; then . "$PRIMARY_ROOT/.kata-flight/workspace"; elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"; fi
   [ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
   echo "KATA_FLIGHT_CONTEXT_ROOT=$KATA_FLIGHT_CONTEXT_ROOT"                            # capture — env dies with this shell
   ```
   Carry `<KATA_FLIGHT_CONTEXT_ROOT>` forward as a literal. Resources live in the tracked
   configured context root (`/context/...`, `/rdr/evidence/...`), not
   the gitignored consumer-repo `_rdr/`. (The launch prompt path is resolved in
   gate 5 via the engine, not derived here.)
2. **Auto-review fires in linked worktrees.** Triage's spine is the
   per-commit auto-reviews the roborev `post-commit` hook produces; that hook
   must run for commits made in the worktree, not just the primary checkout.
   Resolve the hook directory the same way roborev does: if
   `git config --path core.hooksPath` is set, use it as absolute or resolve it
   relative to the main checkout root (`dirname "$(cd "$(git rev-parse
   --git-common-dir)" && pwd -P)"`); otherwise use
   `<main-checkout>/.git/hooks`. Confirm `<hooksPath>/post-commit` exists,
   is executable, and contains `roborev`. If not → refuse with
   `stopped:worktree-autoreview-unconfirmed` (else triage would silently find
   zero findings). Do not edit git config to fix it — surface it.
3. Every input `<RDR_PATH>` exists. For each RDR, read its
   `**Predecessors**:` field (one comma-separated line, may end with a
   period; absent → skip). Per entry,
   take the leading `cli/MMMM` ref (ignore any `(…)` gloss) and resolve its
   RDR via `<rdr-dir>/MMMM-*.md`. **The predecessor RDR is the source of
   truth:** accept iff its `- **Status**:` line reads `Implemented` or
   `Final`; else (`Draft`, missing RDR, …) refuse, naming it. In a coupled
   run, a predecessor that is also in `RDR_PATHS` is allowed only if the
   RDR text records that coupled implement-ordering constraint; otherwise
   refuse `stopped:unimplemented-predecessor:<ref>`. Do **not**
   gate on the predecessor's `status.md` — that launch-flow scaffolding may
   be absent (pre-convention RDRs) or formatted differently, and says
   nothing about whether the RDR is done. (RDRs live in the RDR docs repo,
   e.g. `process/rdr/cli/NNNN-slug.md`.)
4. Resolve `LAUNCH_PROMPT` (inline body → `@<PROMPT_PATH>` → engine default).
   For the default, invoke `/rdr-implement --launch-prompt-path` via the Skill
   tool — it short-circuits to just the path. Pass the path (not the body)
   into the phase briefs. If a path (engine default or `@`) is unreadable →
   refuse, reporting the path tried.

## Phase 1b — Parent creates the worktree

Per `§phase-1b-worktree-creation` (`SHORT_ID` names the worktree):

- **§repo-anchor re-assert** (`git rev-parse --show-toplevel ==
  $REPO_ROOT`) before create; `stopped:repo-anchor-drift` on failure.
- **Raw Bash `git worktree add`, no `EnterWorktree`/`ExitWorktree`**
  (see §phase-1b §worktree-creation-rationale): `git -C "$REPO_ROOT"
  worktree add -b worktree-<SHORT_ID>
  "$REPO_ROOT/.claude/worktrees/<SHORT_ID>" "$TARGET_BRANCH"`. Works
  from any launch context; the parent's CWD is never moved.
- Verify per §phase-1b step 2 (branch exists, parent anchor still
  primary, primary tree clean, worktree HEAD == `TARGET_BRANCH` HEAD).
  Record `WORKTREE_PATH` (absolute) and `BRANCH`.
- Failure → remove any partial worktree; refuse. (No lock to release.)

## Phase 1 — Launch (parent runs launch.md's orchestrator role)

The parent **is** the orchestrator — it does not wrap the launch in a
sub-agent. It drives `LAUNCH_PROMPT` (the engine path from gate 5, or an
inline body; `{RDR_PATHS}` = ordered input list,
`{PRIMARY_RDR_PATH}` = first input, `{RDR_RESOURCES}` =
`<KATA_FLIGHT_CONTEXT_ROOT>/context/rdr-resources.md`, absolute). Each phase brief carries
the path; the phase sub-agent Reads it (the parent never loads the body):

- **Prechecks** (resume / predecessors / test-framework) — parent runs
  these directly via absolute `<art>`/RDR paths. No `cd`. (Predecessor
  doneness already cleared by pre-flight gate 4; launch.md's own
  `status.md`-based precheck is redundant — defer to the gate's RDR-`Status:`
  result, don't re-gate on scaffolding.)
- **Phases 0/1/2/3** — parent spawns **one phase sub-agent at a time** via
  `Agent(subagent_type: "general-purpose")` (Phase 3a/3b in parallel per
  launch.md), reading only each sub-agent's ≤200-word summary. Each phase
  sub-agent's brief carries the pre-created absolute `WORKTREE_PATH` +
  `BRANCH`; its **first Bash call is `cd <WORKTREE_PATH>` then the
  `§worktree-isolation-gate`**:
  ```sh
  [ "$(pwd -P)" = "<WORKTREE_PATH>" ]
  [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
  [ "$(git branch --show-current)" = "<BRANCH>" ]
  ```
  Any failure → that sub-agent returns `stopped:worktree-isolation-failed`
  (no edits) and the parent halts the launch. Each carries the
  `§worktree-invariant` **and `§scope-discipline` verbatim**. All
  commits land on `<BRANCH>`.

  `§scope-discipline` applies with one reframe: a launch phase's "unit
  of work" is the RDR's REQ set for that phase, or the combined REQ set
  for a coupled run, not a single named
  file — so the in-scope surface is wider than a kata's. Both standing
  rules still hold (never-weaken-an-unrelated-test → a pre-existing
  failure outside the RDR's surface is a recorded deviation, not an
  edit; writes worktree-only — `$KATA_FLIGHT_CONTEXT_ROOT` is *read* for
  `{RDR_RESOURCES}`, never written). Launch has no single-`in_scope_paths`
  report field; the per-phase `git status --porcelain`-clean rule below +
  triage's per-commit reviews are the post-fact scope check.

Load-bearing rules the parent enforces across the phases:

- **Commit cadence (triage + crash-safety):** the implementing phase
  commits each green increment as it lands — per-REQ or per-cluster, not
  one batch. (1) triage's spine is per-commit auto-reviews, so uncommitted
  work is invisible; (2) a stall then loses at most one increment. Every
  phase ends with a clean worktree (`git status --porcelain` empty); never
  declare `complete` with uncommitted changes.
- **Output-channel resilience:** if a Bash/tool result is empty or
  truncated, retry that one call a few times before trusting it — dropped
  output is a transport glitch. If the channel stays unusable so progress
  can't be verified, halt the launch as
  `incomplete:output-channel-unstable` (transient → resume candidate), not
  a spec blocker, after committing any verified green increment.
- **Unattended override:** launch.md stops for a genuine design decision;
  here it does **not** — a `needs author decision` deviation is recorded in
  `deviations.md` and the run **continues to the COMPLETION GATE** as an
  open item, not a halt. Mechanical deviations follow launch's normal rules.
  Never ask the user.
- **Ultrathink the hard increments:** each phase sub-agent's brief tells it
  to ultrathink before any structural / cross-subsystem /
  `project_core_principles`-touching / RDR-interpretation increment, reading
  the governing RDR + `{RDR_RESOURCES}` first. Reinforces launch.md's own
  rigor; doesn't replace its phase content.
- **RDR-scoped kata label:** any kata a phase files (implementer-surfaced
  bug / rdr-seed) carries `src:roborev` + `<BATCH_LABEL>` (single RDR:
  `batch:rdr-<NNNN>`; coupled: `batch:rdr-<NNNN>-<MMMM>` or
  `batch:rdr-<first>-plus<N>`) — the phase brief states this. Same key
  triage uses, so one `/kata-flight --label <BATCH_LABEL>` ships
  everything this run produced.
  A filed `type:bug` is also stamped `lifecycle:filed` (in the backlog,
  not yet triaged-ready; `lifecycle:*` is single-valued — triage replaces
  it with `lifecycle:queued` when it deems the kata drainable); a
  `kind:rdr-seed` gets **no** `lifecycle:*` (it exits to RDR authoring).

**Launch outcome** the parent carries into the gate: `complete` |
`incomplete:<blocker>` | `incomplete:output-channel-unstable` |
`stopped:worktree-isolation-failed`; plus `head_sha` (short), worktree
`dirty` count (0 when `complete`), `open_author_decisions` count.

## Phase 1 gate (parent; read-only)

The parent ran the phases, so it holds the launch outcome directly.
Confirm it against ground truth before triaging: read `<art>/status.md`
(match the `COMPLETE`/`INCOMPLETE` token anywhere in the header line, not
only leading — a phase agent may write a `# Status — … COMPLETE` heading)
AND `git -C <WORKTREE_PATH> status --porcelain` (the `dirty` count must
agree with the outcome). Then:

- `stopped:worktree-isolation-failed` → remove the worktree
  (`git worktree remove <WORKTREE_PATH>`; nothing was written); refuse.
- `incomplete:output-channel-unstable` → **STOP** as a *transient* halt.
  Report it as a resume candidate (the work isn't blocked — the pipe was);
  leave the worktree intact. Distinct from a spec blocker.
- `incomplete:<other>` → **STOP**. Report the blocker. Do **not** run
  triage. Leave the worktree intact for resume.
- `complete` but worktree **dirty** (`git status --porcelain` non-empty)
  → **STOP** `stopped:complete-but-uncommitted (<n> files)`. Do **not**
  run triage: triage reads per-commit auto-reviews, so uncommitted work is
  invisible and triage would silently find nothing. The fix is to commit
  the increment (a resume does this first; see Resume); only then is the
  COMPLETE genuine. Never proceed to Phase 2 on a dirty tree.
- `complete` and worktree clean → Phase 2.

## Phase 2 — Triage (parent invokes /roborev-triage directly; only on COMPLETE)

The parent invokes `/roborev-triage <RDR_PATH...> --batch-label <BATCH_LABEL>`
**directly via the Skill tool** — not wrapped in a sub-agent (its own
per-finding sub-agents must dispatch from the top level). `--batch-label
<BATCH_LABEL>` overrides triage's dated default so its katas carry the
run-scoped RDR key, not a same-day-colliding one. Triage is
already unattended and worktree-aware: collects the per-commit
auto-reviews, grounds each against all `RDR_PATHS` + `{RDR_RESOURCES}`,
routes to drop/fix-now/kata-bug/rdr-seed, files self-contained kata
(baking any unresolved question into the body), commits FIX-NOW edits on
`<BRANCH>`, never asks. Pass no merge instruction.

Because `/roborev-triage` freezes `HEAD`/`BASE` from **cwd**, the parent
`cd`s into `<WORKTREE_PATH>` for this step (then back to `TARGET_BRANCH`
primary after) — the one bounded exception to parent-stays-out. Re-run the
`§worktree-isolation-gate` after the `cd`, before invoking the skill;
isolation failure → `stopped:worktree-isolation-failed`, leave worktree
intact. The parent surfaces triage's report block (counts + the
`<BATCH_LABEL>` batch label) verbatim in the final report.

## Phase 2 gate (parent; read-only)

- `stopped:worktree-isolation-failed` → leave the worktree intact (launch
  work is real and unmerged); STOP and surface — triage can be re-run.
- `ok` **and no landing flag** → final report (branch left UNMERGED).
- `ok` **and `--ship`/`--close-and-flight`** → Phase 3.

## Phase 3 — Land-ship (only with --ship or --close-and-flight)

Cite [`lib-land-rdr`](../lib-land-rdr/SKILL.md) **§land-ship** —
**read it first.** Thread its inputs from the warm context (`REPO_ROOT`,
`WORKTREE_PATH`, `BRANCH`, `TARGET_BRANCH`, `RDR_PATHS`, `merged_sha`
captured here). The parent spawns the single ship sub-agent
(`§phase-3-ship-agent`): rebase-if-`TARGET_BRANCH`-moved →
`go test && golangci-lint` on the rebased tip → squash → `merge
--ff-only` → teardown. A green rebased tip is the only gate (a triage
fix-now commit ships if green — no extra fix-now branch).

Capture `merged_sha`. On any `§land-ship` `stopped:*` (test/lint fail,
rebase conflict, ff-reject) → **STOP**, leave the worktree intact, surface
the reason; do **not** run Phase 4 (the code is not on main, so the RDR
is not Implemented). With `--ship` (not `--close-and-flight`): a clean
ship → final report (the RDR/kata/flight steps are intentionally skipped).

## Phase 4 — Land docs + kata + flight (only with --close-and-flight)

Runs only after a clean Phase 3 ship. Cite `lib-land-rdr` **§land-rdr-docs
→ §land-kata-close → §land-flight** in order, threading the warm inputs
(`PROCESS_ROOT`, `RDR_PATHS`, `NNNN_LIST`, `SLUGS`, `ART_DIRS`,
`BATCH_LABEL`, `merged_sha`):

1. **§land-rdr-docs** — spawn the docs sub-agent: one `docs(rdr): <SHORT_ID>
   implemented (consumer-repo <merged_sha>)` commit on `the configured RDR docs branch` flipping each
   RDR `Status` → `Implemented`, each README index row, and each matching
   matrix cell; stage every artifacts dir. Never touches
   `rdr-resources.md`. `stopped:process-wrong-branch` /
   `readme-row-missing:<NNNN>` → halt with the named reason (code is
   merged; the docs flip is incomplete — recoverable + forward-idempotent
   per the lib Failure ladder).
2. **§land-kata-close** — bounded parent step (`cwd` = `REPO_ROOT`; `kata`
   binds project by cwd): close every `kind:rdr-tracked` tracker
   (`tracks: cli/<NNNN>`) with typed evidence citing `<merged_sha>`
   (`kata close <id> --done --commit <merged_sha> --evidence test:… --message
   "<≥40>"`); leave the `<BATCH_LABEL>` bug children open; report the
   open-children count for `<BATCH_LABEL>`.
3. **§land-flight** — 0 open children → `flight: nothing-to-drain`. Else
   invoke `/kata-flight --label <BATCH_LABEL> --drain` **at the top
   level** (it fans out its own ship agents), redirect its output to
   the primary `<ART_DIR>/flight.md`, read back only a ≤200-word digest.

## Final report, then STOP

Without a landing flag, do **not** rebase, ff-merge, or remove the
worktree (the original contract). With `--ship`/`--close-and-flight`, the
branch is merged + torn down by Phase 3 and the report reflects the
landing.

```
rdr-implement-triage: <RDR_PATH...>   [mode: build-only | --ship | --close-and-flight]
  launch:   complete | incomplete(<blocker>)
  open author-decision deviations: <n>   (<art>/deviations.md)
  triage:   <roborev-triage's report block, incl. the batch label>   (omitted if incomplete)

  # build-only (no landing flag):
  worktree: <WORKTREE_PATH>   branch: <BRANCH>   (intact, UNMERGED)
  to land:  review <art>/triage.md + filed kata, then
            /rdr-implement-land <RDR_PATH...>   (or your normal ship flow);
            /kata-flight --label <BATCH_LABEL> --drain for the bug children
            (RDR-scoped key; standing ship-ready queue is `kata ready --label lifecycle:queued`).

  # --ship / --close-and-flight (the landing tail ran — lib-land-rdr Composite report):
  ship:    shipped <merged_sha> | stopped:<reason>
  rdr:     Status→Implemented · README✓ · matrix:<edited|none>   (docs <docs_sha> on the configured RDR docs branch)   [--close-and-flight]
  kata:    tracker <closed <short_id>|already-closed|none>                                              [--close-and-flight]
  flight:  nothing-to-drain | drained <n>/<m> (<k> held)   (<art>/flight.md)                      [--close-and-flight]
```

## Resume

Per `§resume-mechanics`. `--resume <RDR_PATH...>`:

1. Recompute `SHORT_ID` from the ordered RDR list, then locate the
   worktree via `git worktree list` for `worktree-<SHORT_ID>`.
   Worktree gone but branch exists → re-attach (parent, worktree-only):
   `git worktree add .claude/worktrees/<SHORT_ID> worktree-<SHORT_ID>`.
   Both gone → refuse.
2. **Protect uncommitted progress first.** A resumed worktree is expected
   to be dirty — that's normal, not a refusal. The resume phase sub-agent's
   **first action** (after the isolation gate) is to commit any
   already-verified-green increment as its own commit, *before* continuing
   new work. This makes the prior session's work durable, feeds it to the
   triage spine, and avoids building on an uncommitted pile. If green-ness
   can't be confirmed from `<art>/coverage.md`, commit what passes the
   suite and record the rest as still-red in `status.md`.
3. Read `<art>/status.md` (tolerant header match, per the Phase 1 gate).
   `INCOMPLETE` (incl.
   `output-channel-unstable`) → re-enter Phase 1; the parent (via
   launch.md's precheck) picks up the next phase via `status.md`.
   `COMPLETE` but dirty → commit the
   increment (step 2) then re-evaluate the Phase 1 gate. `COMPLETE`, clean,
   no `<art>/triage.md` → run Phase 2 only. `COMPLETE` + triage done →
   already finished; report and stop.
4. Resume does **not** require re-pasting the launch prompt: launch's own
   resume reads on-disk `<art>/*.md` to pick up the next phase, so an
   inline-pasted body is needed only on the first run. If Phase 1 must
   restart from scratch (no `status.md` at all), re-supply the prompt.

## Failure modes

| Condition | Action |
|---|---|
| Primary checkout dirty / no branch | Refuse (`§preflight-shared`). |
| Predecessor RDR `Status:` not `Implemented`/`Final` (or RDR missing) | Refuse; name it. Don't create a worktree. (Gate reads the predecessor RDR, not its `status.md`.) |
| Worktree auto-review unconfirmed (resolved post-commit hook missing, non-executable, or not roborev) | Refuse `stopped:worktree-autoreview-unconfirmed`; don't edit git config — surface it. |
| Launch prompt unresolvable (no inline body; `@<PROMPT_PATH>` unreadable) | Refuse; report the path tried. |
| `/rdr-implement --launch-prompt-path` returns `stopped:no-rdr-flow-home` (stale marker pre-dating the engine split) | Refuse, surfacing it; refresh the marker (`/rdr-init`). |
| `git worktree add` fails | Remove any partial worktree; refuse. |
| Phase sub-agent `stopped:worktree-isolation-failed` | Phase 1: parent halts the launch, removes worktree (no edits) + refuses. Phase 2 (triage `cd`): leave worktree (launch work real) + surface. |
| Launch `incomplete:<spec blocker>` | STOP at the blocker; skip triage; leave worktree for `--resume`. |
| Launch `incomplete:output-channel-unstable` | STOP as *transient*; report as a resume candidate (work not blocked, pipe was); leave worktree. `--resume` retries. |
| Launch `complete` but worktree dirty | `stopped:complete-but-uncommitted (<n>)`; skip triage (uncommitted = invisible to triage); `--resume` commits the increment first. |
| A phase agent would ask the user | Override: record as a deviation + continue. Never surfaces. |
| Triage raises anything interactive | It can't — unattended; tension is baked into the kata. |

## See also

- `/rdr-implement` — the **attended, solo** sibling this wraps: same Stage-8
  launch.md orchestrator, but it stops for a genuine author decision and ends
  at the green branch with **no** triage. Use it when you want a human in the
  loop and no roborev step; use this skill for the unattended launch+triage run.
- `worktree-ship-pipeline` — isolation anchors cited here; **read first**.
  The build phases do **not** use its rebase/refine/merge phases; the
  `--ship` landing phase reuses its `§phase-3-ship-agent` (via
  `lib-land-rdr §land-ship`).
- [`lib-land-rdr`](../lib-land-rdr/SKILL.md) — the landing tail the
  `--ship` / `--close-and-flight` flags cite (`§land-ship`,
  `§land-rdr-docs`, `§land-kata-close`, `§land-flight`). Same anchors as
  `/rdr-implement-land`.
- `/rdr-implement-land` — the **standalone** lander; cite it (or your
  ship flow) when build-only mode leaves a branch, or to land an attended
  `/rdr-implement` branch from a cold start.
- The RDR launch prompt — a path each run (inline body or `@<PROMPT_PATH>`
  override; default from `/rdr-implement --launch-prompt-path`, the engine's
  prompt-location contract). Never hardcoded; carries no roborev/kata
  dependency.
- `/prompt-ship` — the sibling whose inline-body-or-path input mode this
  mirrors.
- `/roborev-triage` — the Phase-2 chained triage (unattended).
- `/kata-ship`, `/kata-flight` — the same thin-orchestrator mold; ship the
  filed `<BATCH_LABEL>` `type:bug` children once you're back.
- `git worktree add` (raw Bash, no `EnterWorktree`) — parent-only
  (§phase-1b-worktree-creation); sub-agents `cd` in instead.
