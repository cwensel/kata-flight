---
name: kata-flight
argument-hint: <short-id…> | --priority N | --parent <id> | --label <name> [--no-review --confirm --drain]
description: 'Use to ship a batch of katas selected by ids, priority, parent, or label. Orders the wave, runs scope review by default, then invokes kata-ship per kata. Trigger for ship all/label/priority katas or $kata-flight.'
---

# kata-flight

Resolves a batch of katas, orders them (deps + priority), and ships
each by invoking `/kata-ship --prepared` sequentially **at the top
level** — never wrapped in a sub-agent, because kata-ship spawns its
own phase agents and a sub-agent cannot spawn (§Why no per-kata
sub-agent).

## Usage

```
/kata-flight <short-id> [<short-id> ...]
/kata-flight --priority <N>        # exact priority (0..4; 0 = highest)
/kata-flight --max-priority <N>    # priority ≤ N
/kata-flight --parent <short-id>   # direct children of umbrella kata
/kata-flight --label <name>        # katas carrying this label (repeatable)
/kata-flight --parent <id> --drain # re-sweep the umbrella until it stays empty
/kata-flight --label <name> --drain # re-sweep the label until it stays empty
/kata-flight --label <name> --confirm    # opt-in: human-gate the review's closes/demotes
/kata-flight --label <name> --re-review  # opt-in: re-ground already-reviewed katas
/kata-flight --label <name> --no-review  # skip the scope-review gate (ship as-resolved)
```

Multiple selectors → union (deduped). Repeated `--label` → OR (any
match). No arguments → print this Usage (`--help`). A selector present
but resolving empty → refuse.

**The scope-review gate runs by default** — `/kata-scope-review`
front-loads at the head of **every wave** (wave 1 and each `--drain`
re-sweep), so only in-scope `lifecycle:reviewed` katas reach the ship
loop and spin-offs pass the same gate before shipping (§Review gate). It
is cheap on a re-flight: already-`lifecycle:reviewed` katas are
skip-filtered, so only new/unreviewed members are re-grounded. The review
disposes autonomously by default (no human prompt). Three opt-in flags,
all off by default and forwarded verbatim: `--re-review` re-grounds
already-reviewed katas (e.g. after new RDRs land); `--confirm`
human-gates the review's irreversible closes/demotes; `--no-review` skips
the gate entirely (ship as the bare per-kata loop).

`--drain` requires at least one **standing selector** (`--parent`/
`--label`) and runs successive waves until those selectors stop yielding
new eligible katas — the only way a flight picks up katas filed after it
started, including mid-flight `KATA_PUSH` katas. `--priority`/explicit
ids are wave-1 snapshots, never re-swept (§Drain). Default: single wave.
`--drain` governs only **re-sweeping**, not tagging: a `KATA_PUSH`
spin-off is tagged onto the flight's standing selectors it genuinely fits
*regardless* of `--drain` (per-kata loop step 3), so even a single-wave
flight's spin-offs keep their batch thread instead of orphaning.

**`--help` (or no arguments).** Print the Usage block above plus these
selector/`--drain` notes, then stop — no gates, no git/roborev/kata
queries, no resolution. A bare invocation is a usage request, not a
flight (only a *present-but-empty* selector refuses).

## Why no per-kata sub-agent

`/kata-ship` is a **spawning** skill — it runs each resolve/refine/ship
phase in a spawned `Agent`, which is legal only from a context that can
spawn. **A sub-agent cannot spawn** (`Task is not available inside
subagents`). So a per-kata wrapper sub-agent would push kata-ship's
phase spawns to L2, where they refuse and the ship stalls. The
orchestrator invoking `/kata-ship` directly (an inline `Skill` call,
which stays in the orchestrator's context) keeps it at L0, where the
phase spawns are legal L0→L1.

Isolation is **not** sacrificed by staying flat. kata-ship runs each
leaf phase in its own isolated agent that returns a verdict only
(worktree-ship-pipeline §leaf-agent-contract); the orchestrator keeps
those verdicts and **surfaces a one-line summary per leaf**, never the
raw phase reports. What stays top-level is the *orchestrator*, not the
leaves — it must remain at L0 because it has to spawn (a sub-agent
can't), and the leaf agents spawn legally L0→L1 from there.

`/goal` and `/loop` are not used — they share the calling conversation's
context, which defeats the orchestration boundary (one verdict per kata,
prep ops parent-owned).

## Invariants

- **Sequential** — kata-ship's ff-merge against the captured
  `TARGET_BRANCH` rules out parallelism.
- **Frozen list (per wave)** — each wave's batch is resolved once and
  stays frozen while it ships; katas filed mid-wave are not spliced in.
  No `--drain`: one wave — re-invoke for a fresh sweep. `--drain`: each
  wave is still frozen, but the flight runs successive waves (§Drain).
- **Ship in-context, never in a sub-agent** — the orchestrator invokes
  `/kata-ship --prepared` itself at the top level so kata-ship can spawn
  its own isolated leaf agents (§Why no per-kata sub-agent;
  worktree-ship-pipeline §leaf-agent-contract). Each leaf returns a
  verdict only; the orchestrator surfaces a one-line summary per leaf,
  not raw phase reports, then verifies the kata state afterward (loop
  step 4).
- **Orchestrator owns the prep ops** kata-ship's `--prepared` expects
  done: kata claim (Phase 1a) and worktree create (Phase 1b, per
  worktree-ship-pipeline §phase-1b-worktree-creation — a raw Bash `git
  worktree add` with **no `EnterWorktree`**, which works even when the
  orchestrator was itself launched into a cwd-pinned context at the repo
  root). Allowed orchestrator ops: read-only `kata`/`git`/`roborev`
  queries, kata claim/label/comment/unassign/edit, `git worktree add` +
  `git worktree remove` + `git branch -d` for cleanup, and the
  `/kata-ship` Skill call itself.
  Forbidden: any direct file edit, any state-mutating `git` command in
  the primary checkout other than the worktree lifecycle ones above,
  any `cd` into a worktree. (Code edits happen inside kata-ship's
  phase agents, never in the orchestrator.)
- **Clean up your own debris; surface anyone else's.** Worktrees and
  claims the orchestrator created are its responsibility — if a
  ship stops without finishing, the orchestrator either leaves
  them intact for `--resume` (when explicitly resumable) or tears
  them down with a clean kata comment. Pre-existing debris from
  other sessions (stale worktrees at flight start, lingering owners
  not matching this session) → surface and halt.
- **Stop-tiebreakers surface; finding-tiebreakers auto-dispose** —
  roborev-finding tiebreakers (1, 2, 4) are decided from evidence and
  applied in-flight without asking (§tiebreakers-shared); only 3
  (rebase conflict) and 5 (multi-target auto-mode) raise
  `AskUserQuestion`. kata-ship runs in-context; the orchestrator does
  not intercept or relay the stops it does raise.
- **Verdict is verified, not reported** — a kata counts `shipped` only
  when `kata show` confirms closed + unlabeled + unowned (loop step 4),
  never because kata-ship narrated success. The orchestrator trusts
  kata state, not the inline report.

## Resolution

1. **Build candidate set** from selectors:
   - explicit ids: trust as given
   - `--priority N`: `kata list --priority N --status open --json`
   - `--max-priority N`: `kata list --max-priority N --status open --json`
   - `--parent <id>`: `kata show <id> --json` → top-level
     `.children[]`, take each `.short_id` (their `.status`/`.owner`/
     `.labels[]` are present here too, so step 2 needs no extra call).
   - `--label <name>` (repeatable): `kata list --status open --json` once,
     keep items whose `labels[]` contains any of the requested names
     (OR across labels; case-sensitive). Bump `--limit` high enough to
     cover the project (`kata labels --json` gives a count if needed).

   > **kata `--json` shape (canonical — don't re-derive it; flow#7cjs):**
   > `kata list --json` returns an **object** `{kata_api_version, issues:[…]}`,
   > **not** a bare array — iterate `.issues[]`, never `.[]` (the latter throws
   > *Cannot index number with string "labels"*). Labels are **bare strings** at
   > `.issues[].labels[]`. On `kata show --json`, labels are **objects** at the
   > top-level `.labels[].label`, and **`.issue.labels` is `null`** — never read
   > it (throws *Cannot iterate over null*). Three shapes for one field; this is
   > a kata-CLI bug (flow#7cjs), not your query. **Prefer the tested helpers
   > in engine `scripts/kata-q.sh`** (`kq_ready_ids`, `kq_owned_by`, `kq_links`,
   > `kq_blockers`, …) over hand-written `jq`; never `jq '.[]'` over `kata
   > list --json`. `owner` is absent on unowned list items — read it null-safe.
2. **Filter ineligible** (silent, log count). Prefer the `kata ready`
   primitive — it *is* the eligibility definition (open + no open blocker),
   composed with label filters (see the consumer label vocabulary reference):
   `kata ready --label <selector> --unowned --no-label kind:rdr-seed
   --no-label inbox:hold --no-label umbrella`.
   For `--parent`, intersect `.children[]` with the `kata ready` set.
   Equivalent manual filter when reading a `kata list`/`kata show` payload
   (labels in top-level `.labels[]`; `.issue.labels` is `null`, never read it):
   - `owner != null`
   - any phase label: `lifecycle:resolving|refining|shipping`
   - `kind:rdr-seed`, `inbox:hold`
   - `umbrella` — a tracking container, never a shippable unit; its
     *children* enter the flight via the batch label, the umbrella itself does
     not. (Shake-out: without this, an umbrella in a `batch:*` group leaks into
     the ship set and a flight tries to "ship" it.)
   - status != `open`
3. **Per-kata dep query**: `kata show <id> --json` once each; read
   top-level `.links[]` (`.issue.links` is `null`). Blocked-by is
   encoded as `type=="blocks"`, `from`=blocker → `to`=dependent: kata
   `X` is blocked by each `L.from.short_id` where `L.type=="blocks"`
   and `L.to.short_id==X`. Keep those whose blocker is also in the batch.
4. **Topo-sort** by intra-batch `blocks` edges (blocker ships first),
   breaking ties by **priority** (`.priority` ascending, 0 = highest;
   carried on `.children[]`/`kata list` items, no extra query), then by
   `short_id` for a stable order. Dependency order always wins where an
   edge exists; priority only orders katas with no edge between them.
   Cycle → refuse with the cycle members listed. Cross-batch blockers
   (blocker not in batch and still open) → drop the dependent + log.
5. Output: ordered list `[short_id …]`. Empty on the initial resolve
   → refuse; empty on a drain re-sweep → terminate, not refuse (§Drain).

Surface the resolved list + count + drop reasons to the user once
before starting (drain re-sweeps label it `wave <n>`). No confirmation
prompt (the user invoked with a selector; re-confirming is noise).

## Review gate (default; suppressed by `--no-review`; before the per-kata loop, every wave)

Unless `--no-review` is set, insert this between Resolution and the per-kata
loop, on **wave 1 and every `--drain` re-sweep** — front-loading is what
breaks the flap: a spin-off picked up by a later wave passes the same
scope gate before it can ship, so out-of-scope/dupe spin-offs are closed
at review, not re-shipped. (The original batch also carries un-designed
work — umbrellas, rdr-shaped children — so reviewing only spin-offs would
still let those churn; gate the whole wave.)

1. **Invoke `/kata-scope-review` in-context** over the resolved wave ids
   (a `Skill` call at the top level, like `/kata-ship` — never in a
   sub-agent, §Why no per-kata sub-agent). Forward `--confirm` and
   `--re-review` if set. It is **read-only on git** (mutates only kata
   state), so it runs without a worktree and disturbs no flight invariant.
   The flight orchestrator already owns all kata lock/label state, so
   kata-scope-review's mutations are run by this same context.
2. **Re-resolve eligibility after review.** The review may have closed
   (out-of-scope), merged (dupe → survivor), demoted (`kind:rdr-seed`),
   or held (`inbox:hold`) members. Re-run the step-2/3 **Filter
   ineligible** over the wave: drop anything now `status != open`,
   carrying `kind:rdr-seed` or `inbox:hold`, or
   not carrying `lifecycle:reviewed`. A merge survivor that entered via the review stays
   if eligible. Log what the review removed.
3. **Ship loop** over the survivors (below). `UMBRELLA-SPLIT` and
   strand-risk katas the review surfaced are **not** blocking — they were
   tagged/dropped; the flight continues and the human handles them
   out-of-band.

**Pipeline, don't barrier (qca0)** — the evidence-backed change
(ship-flow-state-machine reference §4.5/§5.3): the review does **not** have to
finish the *whole* wave before *any* kata ships. The per-kata
`lifecycle:reviewed` stamp (step 2) is the synchronization point — it is
the per-kata gate-pass — so a kata may enter the ship loop the moment
**its own** review clears, while its siblings are still under review.
Pipeline accordingly: as each kata earns `lifecycle:reviewed` (and clears
the step-2/3 re-resolve), dispatch it to the per-kata loop rather than
waiting on the barrier. This preserves both safety invariants — every
kata still passes the scope gate before it can ship (the flap-fix holds:
the stamp *is* the pass), and the topo dependency order still holds (a
kata still waits for any in-batch blocker, reviewed-or-not, before it
ships, per Resolution step 4). The whole-wave-then-ship ordering remains
correct as a degenerate case; pipelining only removes the wall-clock the
barrier wasted.

With `--no-review`, skip this section entirely — the wave goes straight
to the per-kata loop.

## Per-kata loop

For each `short_id` in order:

0. **Between-katas gate.** §repo-anchor re-assert
   (`git rev-parse --show-toplevel == REPO_ROOT`), then
   `git -C "$REPO_ROOT" status --porcelain` empty and
   `git -C "$REPO_ROOT" branch --show-current` still matches the
   captured `TARGET_BRANCH`. Any fails → halt + surface (drift, or
   the prior kata's ship left the primary dirty or off-branch — a
   worktree-invariant breach).

1. **Claim** (Phase 1a, parent-only — the orchestrator owns all kata
   coordination state). Mint a synthetic session id matching
   kata-ship's format so its `--resume` ownership check stays
   compatible:
   ```sh
   SESSION_ID="kata-ship/$(uuidgen | tr A-Z a-z | cut -c1-8)"
   # Atomic CAS — fails (exit 5, already_claimed) if owned; never overwrites
   # a live owner, so a concurrent flight can't be silently orphaned.
   kata claim <short_id> --as "$SESSION_ID" --json \
     || { record stopped:lost-claim-race; continue; }   # nothing claimed → nothing to release
   kata label add <short_id> lifecycle:resolving --json   # phase-1 marker
   kata comment  <short_id> --body \
     "flight session $SESSION_ID — phase 1 resolve starting (--prepared)" --json
   ```
   Use `kata-ship/<8-hex>` (not `kata-flight/*`) so the existing
   `--resume` and auto-resume detectors keep working. Use
   `flight session …` (not `ship session …`) in the comment body
   so the audit trail names the actual orchestrator.

2. **Create the worktree** (Phase 1b, parent-only). Per
   worktree-ship-pipeline §phase-1b-worktree-creation — **raw Bash `git
   worktree add` only, no `EnterWorktree`/`ExitWorktree`** (see that
   section's §worktree-creation-rationale):
   - **§repo-anchor re-assert** (`stopped:repo-anchor-drift` on
     failure).
   - Bash `git -C "$REPO_ROOT" worktree add -b worktree-<short_id>
     "$REPO_ROOT/.claude/worktrees/<short_id>" "$TARGET_BRANCH"`
   - Verify per §phase-1b-worktree-creation step 2 (branch exists,
     parent anchor still primary, primary tree clean, worktree HEAD ==
     `TARGET_BRANCH` HEAD).

   Any failure → release the claim and record `stopped:worktree-prep-failed`:
   ```sh
   kata comment   <short_id> --body \
     "flight session $SESSION_ID — worktree creation failed: <one-line reason>; releasing claim." --json
   kata label rm  <short_id> lifecycle:resolving --json
   kata unassign  <short_id> --json
   ```
   `git -C "$REPO_ROOT" worktree remove .claude/worktrees/<short_id>`
   if it partially materialized. Not a `--resume` candidate (no work
   done). Ask user *skip / abort batch*.

3. **Ship the kata in-context.** Invoke `/kata-ship --prepared
   <short_id>` via the `Skill` tool, at the top level — **never in a
   sub-agent** (§Why no per-kata sub-agent). kata-ship isolates each
   phase as a verdict-only leaf agent (worktree-ship-pipeline
   §leaf-agent-contract); the orchestrator surfaces one line per leaf.
   Steps 1–2 did Phase 1a/1b, so `--prepared` verifies them and runs
   the rest.
   - kata-ship auto-disposes finding-tiebreakers (1/2/4) and surfaces
     only the stops (3/5) via `AskUserQuestion`; the orchestrator does
     not intercept either.
   - **When a `KATA_PUSH:` tiebreaker mints a new kata, tag it onto
     this flight's standing selectors that it genuinely fits** — so the
     spin-off keeps the producer↔consumer thread it was born from, and a
     `--drain` re-sweep (or any later `--label <X>` sweep) finds
     it. This is **`--drain`-independent**: batch membership is a fact
     about the new kata, decided once at mint time; `--drain` only
     governs whether *this* flight re-sweeps. Without this, a no-`--drain`
     flight's spin-offs fall into `lifecycle:filed` limbo with only
     `src:`/`severity:` provenance and no batch thread (the orphaning this
     fixes).
     - `--parent <umbrella>` flight → `kata edit <new-id> --parent
       <umbrella>` (lands in `.children[]` — the `--parent` edge, **not**
       `blocks`). ≤1 parent: if it belongs elsewhere, leave it parentless.
     - `--label <name>` flight → `kata label add <new-id> <name>` for
       the standing label(s) the new kata **genuinely fits** (don't force
       a mismatched label just to re-sweep it — the fit gate keeps the
       funnel clean by construction; a wrong-batch tag is a review-stage
       correction, not a silent ship).
     Multiple standing selectors → apply each that fits; either alone
     suffices (the wave unions them).
     - **Track, for `--drain`, whether this tag landed on a standing
       selector** — that is the §Drain re-sweep trigger (a wave that
       tagged ≥1 spin-off has new work to re-sweep; one that tagged none
       skips the guaranteed-empty re-sweep, 3pqk).

4. **Verify** via `kata show <id> --json` — independent of kata-ship's
   self-report (it just ran inline, so trust the kata state, not the
   narration):
   - `status == closed` AND no `lifecycle:resolving|refining|shipping` label
     AND `owner == null` →
     record `shipped` (`merged_sha` from kata-ship's final report).
   - `git worktree list` still shows the kata's worktree → record
     `shipped` but tag `(worktree leaked: <path>)` in the final
     report; don't try to remove it.
   - Otherwise → go to step 5 (auto-resume).

5. **One-shot auto-resume.** If verification missed AND the kata is
   resumable (`owner` matches `kata-ship/*`, has a
   `lifecycle:resolving|refining|shipping` label, kata's worktree still
   listed by `git worktree list`):
   - Invoke `/kata-ship --resume <short_id>` (again in-context, not a
     sub-agent). `--resume`, not `--prepared`: resume picks up an
     interrupted ship past Phase 1b. Mark per-kata attempt count = 2.
   - Re-verify per step 4 (status check only; no further auto-resume).
   - If second verification also misses → record
     `stopped:not-shipped-after-resume`, `AskUserQuestion`:
     *skip / abort batch*. Do not auto-resume a third time.
   - Not resumable (no `kata-ship/*` owner, no phase label, or
     worktree gone) → record `stopped:not-shipped`, ask user
     *skip / abort batch*.

6. **Surface stops cleanly.** When a kata ends as `stopped:*` (after
   step 4 or 5) AND kata-ship didn't post its own closing comment
   (read `kata show <short_id> --json` to check), post one:
   ```sh
   kata comment <short_id> --body \
     "flight:stopped:<reason> session $SESSION_ID — <one-line context>." --json
   ```
   Do not touch labels/owner kata-ship left intact (e.g. for `--resume`
   recoverability). The comment is for the human triaging the failure.

## Drain (`--drain`, requires a standing selector)

Standing selectors are `--parent` and `--label` — queries a newly-filed
kata can match. `--drain` requires at least one (both is fine: the union
is re-swept) and runs successive waves over those **same standing
selectors** until a re-sweep yields no new eligible kata. Without
`--drain`: a single wave ending after the per-kata loop.

Wave 1 is the initial Resolution + per-kata loop. **Track whether the
wave minted new standing-selector work** — the per-kata-loop step-3
`KATA_PUSH` tag records this (it parents the new kata or adds the
standing label). The re-sweep trigger is *whether a fresh tag landed on
one of **this flight's** standing selectors*, not the tagging act itself
(tagging runs `--drain` or not, per step 3). If wave N added **nothing**
to a standing selector, the next re-sweep can only resolve empty, so
**skip it and terminate** (3pqk) — only re-sweep when the wave produced
new eligible work. The monotone-progress guard below still applies to
every wave that *does* run.

Each subsequent wave (run only when wave N added standing-selector work):

1. **Re-resolve the standing selectors only** per their Resolution paths
   (`--parent` → `kata show` `.children[]`; `--label` → `kata list`
   filtered by label), union + dedup, re-apply the step-2/3/4 filters.
   Never re-run priority/explicit-id selectors. This is what sees katas
   filed since the flight began, including mid-flight `KATA_PUSH` katas
   that per-kata-loop step 3 tagged onto a standing selector.
2. **Subtract this flight's terminal set** — drop any `short_id`
   already `shipped`/`skipped`/`stopped` here, and any still owned by
   this `$SESSION_ID`. (Re-shipping an already-surfaced kata would loop.)
3. **Empty → terminate** (normal end, not a refusal); go to Final report.
4. **Non-empty → review-then-ship.** Surface the list (`wave <n>`); run
   the §Review gate first unless `--no-review` is set (so this wave's new/
   spun-off katas pass scope review before shipping), then the per-kata
   loop, then loop to step 1.

Guards:

- **Standing selectors only** — a re-sweep re-resolves only the
  `--parent`/`--label` selectors given, never priority/explicit ids.
- **Monotone progress** — every wave must ship or terminally dispose ≥1
  kata. With the review gate active (the default), a review that
  closes/merges/demotes/holds ≥1 kata **counts as terminal disposition**
  even if nothing ships that wave (the wave still reduced the backlog). If
  a non-empty re-sweep contains
  only already-terminal/owned members (impossible after step 2), treat as
  empty and terminate.
- **`abort batch` ends the whole flight,** with no further re-sweep.

## Final report

Emit a single block to the user:

```
flight: N shipped, M stopped, K skipped [over W waves]
  shipped: <id>=<sha> <id>=<sha> [<id>=<sha> (worktree leaked: <path>)] …
  stopped: <id>=<reason> …
  skipped: <id>=<reason> …
```

The `over W waves` suffix appears only for `--drain` flights (omit it
for single-wave runs). Tallies aggregate across all waves. No per-kata
commentary, no rollups of kata-ship reports.

## Pre-flight refusals (same as kata-ship, checked once)

0. `--help` or no arguments → print Usage, stop (skip gates 1–5).
1. **§repo-anchor.** `REPO_ROOT="$(git rev-parse --show-toplevel)"`;
   refuse `stopped:wrong-repo` unless it matches the configured consumer repo. Worktree
   creation (step 2) uses explicit `git -C "$REPO_ROOT"`, but a leaked
   `cd` would corrupt the anchor itself, so re-assert the one-liner
   (`git rev-parse --show-toplevel == REPO_ROOT`) before each kata's
   worktree create. Use `git -C "$REPO_ROOT"` for all gates below and
   the between-katas gate; pass `$REPO_ROOT` into the `--prepared`
   handoff.
2. `git -C "$REPO_ROOT" status --porcelain` empty.
3. Capture `TARGET_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"`;
   non-empty.
4. `roborev status` exits 0. Do not front-load daemon checks: use
   normal kata/roborev commands. Run `kata daemon status/start` only
   after a normal kata command fails; do not run `roborev daemon ...`
   proactively.
5. `--drain` without a standing selector (`--parent`/`--label`) →
   refuse (nothing to re-sweep).

Selector resolution happens after these gates.

**Stale-lock reclaim (rja8).** A candidate the step-2 filter would drop
for `owner != null` is not always a *live* ship — a crashed/abandoned
session leaves the kata owned (`kata-ship/*`) with a lifecycle label but
no running worktree. Detect a **dead lock** and offer to reclaim it
rather than only surfacing `abort batch`: when the owner matches
`kata-ship/*` **and** `git -C "$REPO_ROOT" worktree list` shows no
`worktree-<short_id>` **and** `git -C "$REPO_ROOT" branch --list
worktree-<short_id>` is empty (a live ship has at least one of these),
the lock is dead. `AskUserQuestion` → *reclaim / skip / abort batch*. On
**reclaim**: clear the phase label (`lifecycle:resolving|refining|shipping`),
`kata unassign`,
then let the kata fall through to normal claim (step 1) this wave. Log
the reclaim in the run record. Conservative by design: reclaim **only**
when *both* worktree and branch are absent — if either exists, treat it
as live debris and surface/halt per the existing invariant.

## Failure modes

| Condition | Action |
|---|---|
| `--help` or no arguments | Print Usage, stop (gate 0; not a refusal). |
| Selector present but empty **initial** resolved set | Refuse with message. |
| `--drain` without a standing selector (`--parent`/`--label`) | Refuse at pre-flight (gate 5). |
| `--drain` re-sweep resolves empty | Normal termination — emit Final report, do not refuse. |
| Cycle in intra-batch deps | Refuse, list cycle members. |
| Pre-flight fail | Refuse, surface failing gate. |
| Between-katas gate fail (primary dirty / branch changed from `TARGET_BRANCH`) | Halt; surface — prior sub-agent breached worktree invariant. |
| Lost claim race in step 1 (`kata claim` exit 5 / `already_claimed`) | Record `stopped:lost-claim-race`; continue with next kata (do not ask). Nothing claimed — nothing to release. |
| `git worktree add` fails in step 2 | Release claim per step 2 cleanup; record `stopped:worktree-prep-failed`; ask user *skip / abort batch*. Not `--resume`. (Launch-context is no longer a cause — raw `git worktree add` works from L0, a pinned orchestrator, and a sub-agent orchestrator alike. A failure here is a genuine repo/disk issue, e.g. a stale path/branch, not the old "every kata fails identically" wall.) |
| kata-ship refuses `--prepared` (precondition missing) | Shouldn't happen after a successful step 2 — orchestrator/skill bug. Release claim + remove worktree; record `stopped:prepared-precondition-failed`; ask user. |
| kata-ship errors / returns unterminated | Verification (step 4) still runs and decides; if it misses, route as not-shipped. |
| kata-ship reports shipped but step 4 verification fails, kata resumable | Auto-resume once (`/kata-ship --resume <id>`); re-verify. |
| Verification fails after auto-resume | Record `stopped:not-shipped-after-resume`; ask user. |
| Verification fails, not resumable | Record `stopped:not-shipped`; ask user. |
| Verified shipped but worktree leaked | Record `shipped`; tag leak in final report. |
| User answers `abort batch` | Stop; report tally + remaining list. |
| User answers `skip` on `stopped` | Continue with next kata. |

## See also

- `/kata-ship` (the underlying single-kata ship; this skill wraps it)
- `/kata-resolve`, `/roborev-refine` (invoked transitively inside kata-ship)
