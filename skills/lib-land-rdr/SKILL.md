---
name: lib-land-rdr
description: 'Shared reference for landing a built RDR implementation: ship branch, update RDR docs, close tracking kata, and run follow-up flight. Not invoked directly; read when RDR landing skills cite it.'
---

# lib-land-rdr

The shared bones of the **landing tail** every built RDR implementation
runs to reach `Implemented`. Mirrors `worktree-ship-pipeline`'s
cited-by-anchor model: **not invoked directly.** Consumer skills
(`rdr-implement-land`, `rdr-implement-triage`) cite the `§<anchor>`
sections below. Renaming any anchor breaks a consumer — treat the
anchor list as a public API.

This file owns the path **from a green, unmerged RDR implementation
branch to `Implemented`**: ship the branch to main, flip the RDR(s) +
indexes, close tracking kata, and (optionally) flight residual bug
children. It deliberately does **not** own the *build* (that is launch.md
/ `rdr-implement-triage` Phase 1) — it starts where the implementation is
COMPLETE and committed.

## Where this runs

The **parent is the orchestrator** and stays top-level (the same
leaf/orchestrator split as `worktree-ship-pipeline §leaf-agent-contract`
and `rdr-implement-triage`): §land-ship and §land-rdr-docs run as
single sub-agents; §land-kata-close is a bounded parent step;
§land-flight invokes `/kata-flight` **at the top level** (it spawns its
own ship agents — a sub-agent can't fan out) but redirects its verbose
output to disk and reads back only a digest. The parent holds only
paths + ≤200-word summaries.

## Inputs every consumer threads in

| Name | Meaning |
|---|---|
| `REPO_ROOT` | consumer primary checkout (absolute); `§repo-anchor` already asserted it matches the configured consumer repo |
| `WORKTREE_PATH` | `.claude/worktrees/<SHORT_ID>` (absolute) — the built branch's worktree |
| `BRANCH` | `worktree-<SHORT_ID>` |
| `TARGET_BRANCH` | consumer primary checkout branch (the ff-merge target; normally `main`) |
| `RDR_PATHS` | one or more RDRs, e.g. `cli/0037-materialize-policy.md`; singular callers pass a one-item list |
| `NNNN_LIST` | 4-digit RDR numbers from `RDR_PATHS` |
| `SLUGS` | RDR basenames without `.md` |
| `ART_DIRS` | launch artifact dirs beside each RDR (`$PROCESS_ROOT/rdr/cli/<SLUG>/`) |
| `BATCH_LABEL` | run-scoped key triage stamped on every bug child (`batch:rdr-<NNNN>` for one RDR) |
| `PROCESS_ROOT` | configured RDR docs root holding the RDRs and indexes; resolved from the Kata Flight seam or RDR binding |
| `KATA_FLIGHT_CONTEXT_ROOT` | the configured Kata Flight context root |

`PROCESS_ROOT` / `KATA_FLIGHT_CONTEXT_ROOT` come from sourcing the workspace marker
or repo-local `.kata-flight/workspace` as `worktree-ship-pipeline §repo-anchor`
does. The consumer resolves them once and threads them in.

---

## §land-ship

**Reuses `worktree-ship-pipeline §phase-3-ship-agent` verbatim.** One
ship sub-agent owns the whole phase; the parent reads only its report.
Spawn `Agent(subagent_type: "general-purpose")` with the
§phase-3-ship-agent brief (`$SESSION_ID`, `worktree_path`, `branch`,
primary `MAIN_WT` = `REPO_ROOT`, `TARGET_BRANCH`,
**§worktree-invariant verbatim**, the `commits_added` list, and
§tiebreakers-shared verbatim). The agent runs that section's six steps
in order:

1. **Pre-merge checks** — `roborev fix --open --list` empty,
   `git -C <WORKTREE_PATH> status --porcelain` empty,
   §worktree-isolation-gate holds, branch == `<BRANCH>`. Failure → stop.
2. **Re-rebase if `TARGET_BRANCH` moved** (it almost always has — main
   advances during a run). `-c rerere.enabled=true -c
   core.hooksPath=/dev/null rebase "$TARGET_BRANCH"`. Conflict →
   tiebreaker 3, WAIT.
3. **Test + lint on the rebased tip** — `go test ./... && golangci-lint
   run ./...`. Failure → stop intact, `verdict: stopped:test_lint_fail`.
   **No auto-refine.**
4. **Squash** (only if >1 fixup) per §squash-rules.
5. **ff-merge** — `git -C <MAIN_WT> merge --ff-only <BRANCH>`. Rejected
   → re-rebase, retry once; second rejection → stop intact.
6. **Tear down** — `git -C <MAIN_WT> worktree remove <WORKTREE_PATH>`;
   `git -C <MAIN_WT> branch -d <BRANCH>`.

**Fix-now policy.** A triage *fix-now* commit on the branch ships like
any other commit: the green gate (step 3, `go test && golangci-lint` on
the rebased tip) is the only gate. There is **no** extra "stop if
fix-now edits exist" branch — a green rebased tip is sufficient to merge.

**Output the parent carries forward:** `merged_sha` (short, from the
§phase-3 report's `merged_sha`), `verdict` (`shipped` |
`stopped:<reason>`), `teardown`. On any `stopped:*`, the parent
**halts the landing here** — do not run §land-rdr-docs / §land-kata-close
/ §land-flight (the RDR is not Implemented until the code is on main).
The worktree is left intact for re-run.

---

## §land-rdr-docs

One bounded sub-agent makes **a single `docs(rdr):` commit on
`the configured RDR docs branch`** in the RDR docs repo that flips all
`RDR_PATHS` to `Implemented` and reconciles the status indexes in lockstep — the atomicity is
the point: it is what prevents the index-drift class (a README that
says `Final` while the file says `Implemented`, which has produced
reconcile-only sessions historically).

**Read-before-Edit is mandatory** on every file below — the Edit tool's
precondition is a prior Read of the exact file; a `grep`/`sed` peek does
**not** satisfy it. Read each file fully before editing it.

Spawn `Agent(subagent_type: "general-purpose")`. Brief carries
`PROCESS_ROOT`, `RDR_PATHS`, `NNNN_LIST`, `SLUGS`, `ART_DIRS`,
`merged_sha`.
The agent:

1. **Branch guard.** `git -C "$PROCESS_ROOT" branch --show-current` must
   read `the configured RDR docs branch`. If not → return `stopped:process-wrong-branch:<branch>`
   (do **not** commit to whatever is checked out; the RDR-docs working
   branch is `the configured RDR docs branch` by established 0041/0042 precedent). The parent
   surfaces it; the code is already merged, so this is a recoverable
   docs-only halt (re-run after `git -C <RDR_DOCS_REPO> switch <RDR_DOCS_BRANCH>`).
2. **Flip RDR Status lines.** For each
   `$PROCESS_ROOT/rdr/cli/<SLUG>.md`, Read it, then replace the
   `- **Status**:` line so it reads exactly `- **Status**: Implemented`
   — the bare word. The long "Final — locked…" prose is **replaced**,
   not retained (the no-change-history rule). If the line already reads
   `Implemented`, leave it (idempotent re-run).
3. **Flip README index rows.** In
   `$PROCESS_ROOT/rdr/cli/README.md`, Read it, find each `| [<NNNN>]…` row
   in the `## Index` table, and change its Status cell from `Final` to
   `Implemented` (preserve the column padding/alignment of neighbouring
   rows). If the RDR's row is absent → return
   `stopped:readme-row-missing:<NNNN>` (the index is the source of truth
   for the status sweep; a missing row is a real defect, not a
   skip). Already `Implemented` → leave it.
4. **Conditional matrix cells.** In
   `$PROCESS_ROOT/rdr/cli/SMO-FEATURE-MATRIX.md`, **grep first** for an
   `R-<NNNN>` / `cli/<NNNN>` reference for each RDR. If matching SMO×verb
   cells exist, Read the file and update those cells' status markers
   (`●` pending → `✓` shipped) and RDR pointer per the file's legend.
   If **no** matching reference → make **no** edit (most RDRs have no
   matrix cell; that is normal, not a miss). Record `matrix: edited |
   none` in the report.
5. **Never touch `rdr-resources.md`** — it is the evidence index, not the
   status index. Out of scope for landing.
6. **Stage the launch artifacts.** `git -C "$PROCESS_ROOT" add` the
   edited files **and** each artifacts dir in `ART_DIRS` (`req-list.md`,
   `coverage.md`, `verification.md`, `deviations.md`, `status.md`,
   `triage.md` — whichever exist).
7. **One commit.** `git -C "$PROCESS_ROOT" commit` with message:
   ```
   docs(rdr): <SHORT_ID> implemented (consumer-repo <merged_sha>)

   Status Final→Implemented; README index + matrix reconciled.
   ```
   The `(consumer-repo <merged_sha>)` back-reference ties the docs flip to
   the exact merge commit (rebase rewrote the branch SHAs, so cite the
   *merged* sha, not a pre-rebase one).

**Report (≤120 words):** `verdict` (`done` | `stopped:<reason>`),
`status_flipped` (count), `readme_flipped` (count), `matrix`
(`edited`/`none`), `docs_sha` (short), one-line summary.

On `stopped:*` the parent surfaces it and continues to §land-kata-close
only if the stop is purely the matrix/README being already-correct;
a real stop (wrong branch, missing row) halts the landing with the
named reason (code is merged; the RDR flip is incomplete and must be
finished by hand or re-run).

---

## §land-kata-close

A **bounded parent step** (no sub-agent — it is two `kata` calls and a
read). Closes the RDR tracking kata(s); leaves the bug children open.

`kata` binds its project by **cwd**, so run every `kata` call with the
parent's cwd at `REPO_ROOT` (the consumer checkout — katas
resolve against that project). The binary is expected on `PATH`; if it is not,
install it from <https://katatracker.com/> or use the explicit path configured
by the consumer.

1. **Find tracker(s).**
   ```sh
   kata list --label kind:rdr-tracked --status open --json
   ```
   The result is `{"issues":[…]}`. For each RDR, select any issue whose
   `body`/comments carry `tracks: cli/<NNNN>` (the RDR back-reference) and
   take its **`short_id`** (e.g. `bgqd`) — **not** the numeric `id` field.
   `kata close` rejects the legacy numeric id (`"…looks like a legacy issue
   number; use a short_id"`); every `kata` mutation below uses the
   `short_id`. Zero matches → the tracker is **already closed** (the harness
   often closes it at COMPLETE); add a resolution comment to the closed
   tracker if one is findable via `kata search "tracks:
   cli/<NNNN>"` (again by `short_id`), else record `tracker: none` and move
   on. More than one open match for an RDR → close each.
2. **Close with typed evidence** (the close gate requires `--reason
   done` + a typed `--evidence` + a `--message` ≥40 chars; the sugar
   flags satisfy it):
   ```sh
   kata close <short_id> --done --commit <merged_sha> \
     --evidence test:"go test ./..." \
     --message "RDR <NNNN> implemented and merged to main at <merged_sha>; all REQ-N green, indexes reconciled."
   ```
   Confirm the close first with `--dry-run` appended; if the dry-run
   reports a validation error, fix the flags (do not retry blindly) —
   the recurring failure mode is a `--message` under 40 chars or an
   untyped `--evidence`.
3. **Leave the bug children open.** Do **not** touch any
   `<BATCH_LABEL>` kata — those are §land-flight's
   input.

**Report (≤60 words):** `tracker: <NNNN>=closed <short_id> |
already-closed | none`, plus the count of open `<BATCH_LABEL>` children — `kata list
--label <BATCH_LABEL> --status open --json` returns `{"issues":[…]}`, so
count `.issues` (e.g. pipe to `python3 -c 'import sys,json;
print(len(json.load(sys.stdin)["issues"]))'`). That count is what
§land-flight drains.

---

## §land-flight

Sweeps the residual bug children triage filed under `<BATCH_LABEL>`.
**Runs at the top level** — `/kata-flight` spawns
its own per-kata ship agents, and a sub-agent cannot fan out (the
nested-agent wall). To keep its verbose per-kata chatter out of the
orchestrator context, **redirect its output to a file and read back
only a digest.**

1. **Short-circuit on empty.** If §land-kata-close reported **0** open
   `<BATCH_LABEL>` children, do **not** invoke kata-flight — record
   `flight: nothing-to-drain` and finish. (Triage filing nothing is the
   common happy path.)
2. **Otherwise invoke at top level**, capturing output to disk so it
   never enters orchestrator context:
   ```
   /kata-flight --label <BATCH_LABEL> --drain
   ```
   Run it via the Skill tool. kata-flight already runs its
   scope-review-per-wave gate and disposes autonomously. When it
   finishes, write its full report block to the primary `<ART_DIR>/flight.md`, then
   read back **only** the final summary line + per-kata verdict counts
   (≤200 words) into the orchestrator. Never echo the raw per-kata
   stream.
3. **Commit the report.** `flight.md` is authored *after* §land-rdr-docs's
   `git add <ART_DIR>/` staging step (step 6), so the implemented-docs
   commit cannot have swept it in — it must be committed here or it is
   left orphaned (untracked). Make a dedicated trailing commit on
   `the configured RDR docs branch` in `process` (the same docs branch §land-rdr-docs used):
   ```
   git -C "$PROCESS_ROOT" add <ART_DIR>/flight.md
   git -C "$PROCESS_ROOT" commit -m "docs(rdr): <SHORT_ID> flight drain report (<BATCH_LABEL>, <n> shipped)"
   ```
   Skip the commit only in the `nothing-to-drain` case (no file is
   written). Forward-idempotent: a re-run with no new flight changes is a
   no-op (`git add` of an unchanged file stages nothing, so there is
   nothing to commit).

**Report (≤120 words):** `flight: nothing-to-drain | drained
<shipped>/<total> (<stopped> held)`, the path `<ART_DIR>/flight.md`,
and any held-kata short_ids the user should look at.

---

## Composite final report (the consumer assembles this)

```
land: <RDR_PATH...>
  ship:    shipped <merged_sha> | stopped:<reason>
  rdr:     Status→Implemented · README✓ · matrix:<edited|none>   (docs <docs_sha> on the configured RDR docs branch)
  kata:    tracker(s) <closed <short_id>|already-closed|none>
  flight:  nothing-to-drain | drained <n>/<m> (<k> held)   (<ART_DIR>/flight.md)
```

## Failure ladder (where a stop leaves you)

| Stop | State | Recovery |
|---|---|---|
| §land-ship `stopped:test_lint_fail` / conflict / ff-rejected | code NOT merged; worktree intact | fix on the branch; re-run land |
| §land-rdr-docs `stopped:process-wrong-branch` | code merged; RDR NOT flipped | `git -C <RDR_DOCS_REPO> switch <RDR_DOCS_BRANCH>`; re-run from §land-rdr-docs |
| §land-rdr-docs `stopped:readme-row-missing` | code merged; RDR file flipped, index not | add the README row; re-run §land-rdr-docs (idempotent on the file) |
| §land-kata-close tracker not found | code merged; RDR flipped | non-fatal; record `tracker: none`, continue |
| §land-flight kata-flight holds a kata | code merged; RDR done | the held kata is in `<ART_DIR>/flight.md`; resolve it next turn |

The phases are **forward-idempotent**: re-running land after a docs/kata
stop re-flips already-flipped files to no-ops and skips an
already-closed tracker, so a re-run finishes the tail without
double-committing.
