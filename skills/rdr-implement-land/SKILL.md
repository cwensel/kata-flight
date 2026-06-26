---
name: rdr-implement-land
argument-hint: <RDR_PATH> [--no-flight]
description: 'Use to land a built but unmerged RDR implementation branch: rebase, fast-forward merge, update RDR status/indexes, close tracker, and optionally flight follow-up katas. Trigger for land RDR implementation.'
---

# rdr-implement-land

The **landing** half of RDR Stage 8. Where `/rdr-implement` and
`rdr-implement-triage` *build* the implementation onto an isolated
`worktree-rdr-<NNNN>` branch and **stop before merge**, this skill takes
that branch the rest of the way to `Implemented`:

```
ship (rebase→ff-merge→teardown) → flip RDR + indexes → close tracker → flight residual bugs
```

It is the standalone, **unattended** consumer of
[`lib-land-rdr`](../lib-land-rdr/SKILL.md) — **read that first.** Every
phase below cites a `§<anchor>` in `lib-land-rdr` SKILL.md and adds
nothing but the resolution of inputs and the gate sequencing. The
flag-gated `--ship` / `--close-and-flight` phases inside
`rdr-implement-triage` cite the **same** anchors, so the two never
fork.

**Runs on any unmerged rdr branch.** Unlike the triage skill's phases
(which run inside the warm build orchestrator), this skill re-derives
its inputs from disk, so it lands a branch from a cold start — including
one left by the **attended** `/rdr-implement` (no triage, no warm
context). If `triage` never ran, the `batch:rdr-<NNNN>` set is empty and
§land-flight short-circuits.

## Usage

```
/rdr-implement-land <RDR_PATH>              # land fully: ship → flip → close → flight
/rdr-implement-land <RDR_PATH> --no-flight  # ship → flip → close, then EMIT the flight command (don't run it)
```

- `<RDR_PATH>` — the implemented RDR, e.g. `cli/0037-materialize-policy.md`
  (resolves under `$PROCESS_ROOT/rdr/`).
- `--no-flight` — stop after §land-kata-close and print
  `/kata-flight --label batch:rdr-<NNNN> --drain` as a handoff instead of
  running §land-flight inline. Use when you want to eyeball the residual
  bug batch in a separate turn (the historical hand-driven pattern).

## Invariants

- **Never blocks on the user.** No `AskUserQuestion`, no "how should I
  proceed?" checkpoint. Each phase is **pass → continue** or **fail →
  halt with a named `stopped:<reason>`**. A passing gate is silent.
  (Same contract as `rdr-implement-triage`.)
- **Parent is the orchestrator (flat), top-level.** §land-ship and
  §land-rdr-docs run as single sub-agents spawned from the top level;
  §land-kata-close is a bounded parent step; §land-flight invokes
  `/kata-flight` at the top level (it fans out its own agents) with
  output redirected to disk. The parent holds only paths + ≤200-word
  summaries.
- **Order is fixed and gated.** ship → docs → kata → flight. A
  `stopped:*` in ship halts everything (code not merged → RDR is not
  Implemented). A stop later leaves a recoverable, forward-idempotent
  state (see `lib-land-rdr` Failure ladder).
- **Never touches `rdr-resources.md`.** It is the evidence index, not a
  status index.

## Pre-flight (parent; read-only) — pass/refuse, no ask branch

Run all gates; all pass → proceed silently to §land-ship. Any fail →
halt with its named `stopped:<reason>`.

0. **§repo-anchor.** `REPO_ROOT="$(git rev-parse --show-toplevel)"`;
   refuse `stopped:wrong-repo` unless it matches the configured consumer repo. Capture
   `TARGET_BRANCH = $(git -C "$REPO_ROOT" branch --show-current)`
   (non-empty) and require `git -C "$REPO_ROOT" status --porcelain`
   clean (the ff-merge target must be clean).
1. **Resolve the workspace paths from the marker** (the same resolution
   `worktree-ship-pipeline §repo-anchor` uses — worktree-invariant):
   ```sh
   WS="$(dirname "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")"
   KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
   if   [ -f "$PRIMARY_ROOT/.kata-flight/workspace" ]; then . "$PRIMARY_ROOT/.kata-flight/workspace"; elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"; fi
   [ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
   [ -d "$PROCESS_ROOT/rdr" ]  || { echo "stopped:process-not-found:$PROCESS_ROOT" >&2; exit 1; }
   ```
   Carry `KATA_FLIGHT_CONTEXT_ROOT`, `PROCESS_ROOT` forward as literals.
2. **Resolve the RDR + derived inputs.** `<RDR_PATH>` exists under
   `$PROCESS_ROOT/rdr/`. Derive `NNNN` (4-digit), `SLUG` (basename
   without `.md`), `ART_DIR = $PROCESS_ROOT/rdr/cli/<SLUG>/`,
   `BATCH_LABEL = batch:rdr-<NNNN>`.
3. **RDR is locked + built.** Read the RDR's `- **Status**:` line — it
   must read `Final` or already `Implemented` (a `Draft` is not
   landable → refuse `stopped:rdr-not-final`). Read `<ART_DIR>/status.md`
   — it must contain the `COMPLETE` token (anywhere in the header line);
   missing/`INCOMPLETE` → refuse `stopped:implementation-incomplete`
   (the branch isn't built; this skill lands, it does not build).
4. **The branch exists and is unmerged.**
   `git -C "$REPO_ROOT" worktree list` shows `worktree-rdr-<NNNN>` at
   `.claude/worktrees/rdr-<NNNN>` (capture `WORKTREE_PATH` absolute,
   `BRANCH`). If the worktree is gone but the branch exists →
   re-attach (`git -C "$REPO_ROOT" worktree add
   "$REPO_ROOT/.claude/worktrees/rdr-<NNNN>" worktree-rdr-<NNNN>`).
   Both gone but `<RDR_PATH>` already `Implemented` and the
   `<ART_DIR>` shows a recorded merge → **already landed**; report and
   stop (idempotent). Branch missing with `Status: Final` and no merge
   record → refuse `stopped:no-branch-to-land` (nothing built to land).
5. `roborev status` exits 0 (do **not** run `roborev daemon ...`) — §land-ship's
   pre-merge check reads `roborev fix --open --list`.

## Phases (each cites lib-land-rdr verbatim)

1. **§land-ship** — spawn the ship agent (reuses
   `worktree-ship-pipeline §phase-3-ship-agent`): rebase-if-moved →
   `go test && golangci-lint` → squash → `merge --ff-only` → teardown.
   Capture `merged_sha`. Any `stopped:*` → **halt the landing**, leave
   the worktree intact, surface the reason. (A green rebased tip is the
   only gate — a triage fix-now commit ships if green.)
2. **§land-rdr-docs** — spawn the docs agent: one `docs(rdr): <NNNN>
   implemented (consumer-repo <merged_sha>)` commit on `the configured RDR docs branch` flipping
   Status + README row + (conditional) matrix cell, staging the
   artifacts. `stopped:process-wrong-branch` / `readme-row-missing` →
   halt with the named reason (code is merged; the docs flip is
   incomplete — recoverable per the lib Failure ladder).
3. **§land-kata-close** — bounded parent step: close the
   `kind:rdr-tracked` tracker (`tracks: cli/<NNNN>`) with typed evidence
   citing `<merged_sha>`; leave the `<BATCH_LABEL>` children open;
   report the open-children count.
4. **§land-flight** — if 0 open children → `flight: nothing-to-drain`.
   Else, **unless `--no-flight`**, invoke `/kata-flight --label
   batch:rdr-<NNNN> --drain` at the top level, output to
   `<ART_DIR>/flight.md`, read back a ≤200-word digest. With
   `--no-flight`, skip the run and emit the command as a handoff.

Assemble and print the lib's **Composite final report**, then STOP.

## Final report

```
rdr-implement-land: <RDR_PATH>
  ship:    shipped <merged_sha> | stopped:<reason>
  rdr:     Status→Implemented · README✓ · matrix:<edited|none>   (docs <docs_sha> on the configured RDR docs branch)
  kata:    tracker <closed <short_id>|already-closed|none>
  flight:  nothing-to-drain | drained <n>/<m> (<k> held)   (<ART_DIR>/flight.md)
           [--no-flight: handoff → /kata-flight --label batch:rdr-<NNNN> --drain]
```

## Failure modes

| Condition | Action |
|---|---|
| `REPO_ROOT` is not the configured consumer repo / target dirty / no branch | Refuse (`stopped:wrong-repo` / dirty / no-branch). |
| RDR `Status` is `Draft` | Refuse `stopped:rdr-not-final` (nothing locked to land). |
| `<ART_DIR>/status.md` not COMPLETE | Refuse `stopped:implementation-incomplete` (this skill lands, doesn't build). |
| `worktree-rdr-<NNNN>` branch + worktree both gone, RDR already Implemented | Already landed; report + stop (idempotent). |
| Branch gone, `Status: Final`, no merge record | Refuse `stopped:no-branch-to-land`. |
| `roborev status` unhealthy | Refuse; surface the normal command output. Do **not** run `roborev daemon ...`. |
| §land-ship `stopped:*` (test/lint/conflict/ff-reject) | Halt; worktree intact; code NOT merged; re-run after fixing the branch. |
| §land-rdr-docs `stopped:process-wrong-branch` / `readme-row-missing` | Halt with the named reason; code merged; finish the docs flip per the lib Failure ladder (re-run is forward-idempotent). |
| Tracker not found | Non-fatal; record `tracker: none`; continue. |

## See also

- [`lib-land-rdr`](../lib-land-rdr/SKILL.md) — the cited landing tail; **read first**.
- `/rdr-implement` — the **attended** build half (no triage); leaves the
  branch this skill lands.
- `rdr-implement-triage` — the **unattended** build half; its
  `--close-and-flight` flags cite the same `lib-land-rdr` anchors to land
  inline. Use **this** standalone skill to land a branch from a cold
  start (e.g. after an attended build, or in a fresh session).
- `worktree-ship-pipeline §phase-3-ship-agent` — the ship mechanics
  §land-ship reuses.
- `/kata-flight` — the residual-bug sweep §land-flight invokes.
