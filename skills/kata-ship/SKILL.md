---
name: kata-ship
argument-hint: <short-id…> | --resume <id> | --prepared <id>
description: 'Use to ship one or more kata issues end to end: resolve in a worktree, rebase, run roborev refine, fast-forward merge, tear down, and close. Trigger for ship/land kata or $kata-ship.'
---

# kata-ship

Consumer of `worktree-ship-pipeline`. **Read that file first** —
this skill specializes the work source (kata body), identity (kata
short_id), lock (kata.owner + phase labels), Phase-1 resolve agent
(`/kata-resolve`), tiebreaker 4 (`KATA_PUSH:`), and close step
(`kata close`). Every section cited as `§<anchor>` below refers to
`worktree-ship-pipeline` SKILL.md.

**Resolve** → **Rebase + Refine** → **Ship** (ff-merge, tear down,
close).

One rebase per ship (Phase 2a), refine reviews against current
trunk, ff-merge with no bounce-back. Maximum parallelism, minimum
rework. Failures preserve state (owner + phase label + worktree)
for `--resume`. User consulted only on the *stop* tiebreakers (3 rebase
conflict, 5 multi-issue auto mode); the roborev-finding tiebreakers (1,
2, and this skill's `TIEBREAKER_4` `KATA_PUSH:`) auto-dispose from
evidence per §tiebreakers-shared. All five are specified below.

## Usage

```
/kata-ship <short-id> [<short-id> ...]
/kata-ship --resume <short-id>
/kata-ship --prepared <short-id>     # sub-agent entry point; see below
```

No args → auto-pick first unowned, unlabeled issue from `kata
ready --json`. Resolve-only → `/kata-resolve`. Fix-only →
`/roborev-fix`. Refuse if kata already owned/phase-labeled
(`lifecycle:resolving|refining|shipping`),
or the primary checkout has unrelated uncommitted work.

`--prepared` is for sub-agent invocation (e.g. from `/kata-flight`).
The caller has already done Phase 1a (claim) and Phase 1b (worktree
create) in the orchestrator context — a sub-agent cannot create the
worktree itself. Phases 1a + 1b become verify-only; everything else is
unchanged. Refuse if either precondition is missing.

## Parameters (consumed by worktree-ship-pipeline)

| Parameter | Value |
|---|---|
| `EXPECTED_REPO_BASENAME` | `consumer-repo` (§repo-anchor) |
| `WORK_SOURCE` | `kata show <id>` body (resolved by `/kata-resolve` inside the worktree) |
| `SHORT_ID` | kata short-id |
| `BRANCH` | `worktree-<SHORT_ID>` |
| `WORKTREE_PATH` | `.claude/worktrees/<SHORT_ID>` |
| `TARGET_BRANCH` | `$(git branch --show-current)` captured at preflight |
| `INTENT_FIELD` | `resolve_intent_excerpt` |
| `FILES_MAX` | `10` |
| `DELETIONS_MAX` | `300` |
| `TIEBREAKER_4` | `KATA_PUSH:` packet → push out-of-scope finding to a sibling kata (see below) |
| `TIEBREAKER_5` | Multi-issue auto mode where a *stop* tiebreaker (3) fires — pause that issue, ask, continue (1/2/4 auto-dispose, no pause) |
| `LOCK_ANCHOR` | `kata.issue.owner == "kata-ship/<uuid>"` + a phase label (`lifecycle:resolving\|refining\|shipping`) |
| `CLOSE_STEP` | `kata close <id> --done --commit <sha> --message "<≥40 chars>"` after labels → unassign (close requires `--message` + typed `--evidence`) |

The worktree is created per §phase-1b-worktree-creation (raw Bash `git
worktree add`, no `EnterWorktree`); branch is
`worktree-<SHORT_ID>`. Tighter scope thresholds than
`/prompt-ship` because a single kata is meant to be a focused
unit of work.

## TIEBREAKER_4 (out-of-scope finding → push to sibling kata)

Clear **§spinoff-worthiness** first: the agent ultrathinks whether
the finding is worth deferring (a real, reachable defect not already
adjudicated by the RDR/critiques at `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`, scoped
out, or over-engineering — else DROP via `/roborev-respond`, not a
push), attaches to an existing kata before creating, and proposes a
well-reasoned self-contained body.

Emit the `KATA_PUSH:` packet (terse, ≤80 words — the parent files
the body):

- `target` = `<existing short_id>` or `new`
- proposed `title` + §spinoff-worthiness `body` when `new`
- roborev `<severity> <source-anchor>` cite
- one-sentence rationale for why it's out of *this* kata's scope

**Auto-disposed** per §tiebreakers-shared Mechanic (4 does not ask the
user). The packet still routes to the parent, who files the kata — that's
the lock contract (parent owns all `kata` lock/label commands), not a
human gate:

1. Parent runs `kata create` (if new).
2. Parent runs `kata label add <id> src:roborev` (provenance).
3. Parent runs `kata label add <id> severity:<low|medium|high>`
   matching the finding's severity (idempotent; on attach, keep
   any existing higher severity — never downgrade).
4. The agent runs `/roborev-respond` citing the kata short_id and
   re-enters the refine loop.

## Context discipline (kata-specific additions)

Per §context-discipline, plus:

- **Parent owns all `kata` lock/label commands.** Agents may only
  read (`kata show|comment|search`).
- The agent's brief always passes through `$SESSION_ID` verbatim
  so `/kata-resolve --no-lock-mgmt` knows the synthetic owner.

## Coordination

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"   # §repo-anchor
[ -f "$REPO_ROOT/.kata-flight/env" ] && . "$REPO_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$REPO_ROOT")}"
[ "$(basename "$REPO_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$REPO_ROOT" >&2; exit 1; }
SHORT_ID=<kata-short-id>
SESSION_ID="kata-ship/$(uuidgen | tr A-Z a-z | cut -c1-8)"
BRANCH="worktree-$SHORT_ID"
WORKTREE_PATH="$REPO_ROOT/.claude/worktrees/$SHORT_ID"   # absolute, anchored
TARGET_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
PRIMARY_ROOT="$REPO_ROOT"            # == REPO_ROOT in valid parent state; the consumer work repo (resources live in $KATA_FLIGHT_CONTEXT_ROOT, its configured Kata Flight context root)
WS="$(dirname "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")"   # workspace root (worktree-invariant)
KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
if   [ -f "$PRIMARY_ROOT/.kata-flight/workspace" ]; then . "$PRIMARY_ROOT/.kata-flight/workspace"; elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"; fi
[ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
```

Resources are **tracked** in the configured Kata Flight context root, so they need not
materialize inside the consumer worktree — every sub-agent brief passes
`$KATA_FLIGHT_CONTEXT_ROOT` (derived + symlink-safe per §repo-anchor) and the agent
reads `$KATA_FLIGHT_CONTEXT_ROOT/context/...` and `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...` by
absolute path. Configured resources are `context/` (rdr-resources.md,
rdr-env.md, project-guidelines.md) and `rdr/evidence/` (`critique/`,
`3amigo/`, `spikes/`) — **not** the external RDR methodology repo;
don't substitute one.

Each of this skill's three phases (1c resolve, 2 rebase+refine, 3 ship)
runs as a **leaf agent** per `worktree-ship-pipeline` §leaf-agent-contract:
the agent returns a verdict-only report (no raw diffs), and the parent
surfaces a one-line summary. The parent owns all lock/label state.

**Gate:** `.issue.owner == null` AND no phase label. The phase label is
`lifecycle:resolving|refining|shipping` (the phase marker). Fail → refuse
(silent on auto-pick, surface on explicit id). Never strip another session's
lock.

**Phase labels are namespaced + single-valued.** This skill writes
`lifecycle:resolving` (phase 1) → `lifecycle:refining` (phase 2) →
`lifecycle:shipping` (phase 3); a transition is a *replace* (remove the
current `lifecycle:*`, then add the next).

## Pre-flight (parent, hard stops; refuse, do not ask)

Per §preflight-shared (gate 0 §repo-anchor capture+assert / clean
primary checkout / capture `TARGET_BRANCH` + divergence advisory /
`roborev status` 0), plus kata-specific gate 4 and gate 5:

4. `kata show <id> --json`: status `.issue.status == "open"`, and
   `[(.labels // [])[].label]` does not include `kind:rdr-seed`.
   **Read labels from the top-level `.labels[]`** — on `kata show`
   they are objects (`.label`), on `kata list` bare strings;
   `.issue.labels` is NULL, never read it (corpus: drab).
   (`kind:rdr-seed` means deliverable is an RDR draft — no red/green
   test pair, no automatable ship path; see umbrella kata dtr1.)
   There is **no `blocks_on` field** in the CLI JSON — blockers live
   in top-level `.links` (`type:"blocks"`). Don't reinvent topo logic
   in jq; gate on `kata ready` instead, which already excludes any
   kata with an open `blocks` predecessor:
   ```sh
   kata ready --json | jq -e --arg id "<id>" \
     '[.issues[].short_id] | index($id)' >/dev/null \
     || { echo "stopped:blocked-by-open-predecessor" >&2; exit 1; }
   ```
5. Coordination gate above passes.

Auto-pick: gate 5 per candidate; first survivor wins.

## Phase 1 — Acquire + Resolve

### 1a. Acquire

Order: claim → label → comment.

```sh
# Atomic CAS — fails (exit 5, already_claimed) if owned; never overwrites.
# A lost race is the exit code, not a clobber. (--force only in §--resume.)
kata claim <id> --as "$SESSION_ID" --json || exit 1   # refuse; nothing to release
kata label add <id> lifecycle:resolving --json   # phase-1 marker
kata comment   <id> --body "ship session $SESSION_ID — phase 1 resolve starting" --json
```

**`--prepared`:** skip the three commands above. The caller did
them. Adopt `$SESSION_ID` from the existing owner:
```sh
SESSION_ID=$(kata show <id> --json | jq -re '.issue.owner | select(startswith("kata-ship/"))') \
  || { echo "stopped:prepared:owner-not-kata-ship" >&2; exit 1; }
kata show <id> --json | jq -e '[(.labels // [])[].label] | index("lifecycle:resolving")' \
  >/dev/null || { echo "stopped:prepared:missing-phase-label" >&2; exit 1; }
```
Both checks must pass; failures refuse without mutating state.
Don't post the "phase 1 resolve starting" comment — the caller
already posted its own start comment.

### 1b. Parent creates the worktree

Per §phase-1b-worktree-creation, with `name: "<SHORT_ID>"`.
On any failure, in addition to the shared teardown (remove
worktree if partial), release the kata lock:
```sh
kata unassign <id> --json
kata label rm  <id> lifecycle:resolving --json
```

**`--prepared`:** skip worktree creation entirely. The caller
already created the worktree (raw `git worktree add`). Verify it
exists and is on the expected branch (parent-side, read-only):
```sh
git -C "$REPO_ROOT" worktree list --porcelain | grep -q "^branch refs/heads/worktree-<SHORT_ID>$" \
  || { echo "stopped:prepared:worktree-missing" >&2; exit 1; }
[ -d "$REPO_ROOT/.claude/worktrees/<SHORT_ID>" ] \
  || { echo "stopped:prepared:worktree-path-missing" >&2; exit 1; }
```
Failure refuses without mutating state (no teardown — the worktree
the caller built may still be salvageable by `--resume`). Set
`worktree_path = .claude/worktrees/<SHORT_ID>`, `branch =
worktree-<SHORT_ID>` and proceed to 1c.

### 1c. Spawn resolve agent (leaf — §leaf-agent-contract)

`Agent(subagent_type: "general-purpose")`. Brief:

- Kata id, `$SESSION_ID` (verbatim pass-through), parent cwd,
  `TARGET_BRANCH`.
- **`PRIMARY_ROOT`** + **`KATA_FLIGHT_CONTEXT_ROOT`** (absolute, from Coordination;
  agents may also resolve it from the workspace marker — `WS=$(dirname
  "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")`;
  `KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
  Resources live in the configured Kata Flight context root, not the consumer worktree;
  the agent reads RDR resources/critiques and conventions from there —
  e.g. `$KATA_FLIGHT_CONTEXT_ROOT/context/rdr-resources.md`,
  `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/critique/<NNNN-slug>-critique.md`,
  `$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md`. the configured RDR evidence root,
  not the external RDR methodology repo.
- **Pre-created worktree:** `worktree_path` (absolute, from 1b),
  `branch`. The agent does NOT call EnterWorktree. Agent's first
  Bash call is `cd <worktree_path>` + isolation verify per
  §worktree-invariant:
  ```sh
  [ "$(pwd -P)" = "<worktree_path>" ]
  [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
  [ "$(git branch --show-current)" = "worktree-<SHORT_ID>" ]
  ```
  Any failure → return `stopped:worktree-isolation-failed` with
  the failing check; do not edit any file.
- **§worktree-invariant verbatim.**
- **§scope-discipline verbatim.** Commit ONLY the kata's in-scope
  paths (the named fix + its new red/green test + forced callers);
  never weaken/clean up an unrelated test or source to make a broad
  `go test ./...` pass; report the final set as `in_scope_paths`.
- §tiebreakers-shared verbatim, plus the kata-ship `TIEBREAKER_4`
  spec (`KATA_PUSH:`) and `TIEBREAKER_5` (multi-issue auto mode)
  from above. (Tiebreaker 4 won't fire during resolve; pass
  through so vocabulary matches phase 2.)
- Invoke `/kata-resolve <id> --no-lock-mgmt`. The skill detects
  that CWD is already inside a linked worktree (via
  `--no-lock-mgmt` branch) and skips its own worktree-creation
  step. Commit per project conventions; do not push.

  `stopped:*` verdicts citing API unfamiliarity or
  "complex-rdr-implementation" require running kata-resolve
  step 4's precedent check first; if it must still stop, the
  verdict names what was unread
  (`stopped:precedent_unread:<slugs>`).

  A `stopped:needs-triage:<phrase>` verdict is expected when
  read-first reveals the body's scope/precedent doesn't fit the
  seam; emit before any edit and carry the triage question in
  `resolve_intent_excerpt`.
- Tiebreaker protocol: return a `TIEBREAKER:` packet (kata id,
  condition #, ≤80-word context, proposed disposition) per
  §tiebreakers-shared Mechanic.

**Report schema** (≤150 words, no diffs):

- `worktree_path`, `branch`, `head_sha` (short)
- `commit_subject`
- `in_scope_paths`: every path the commit touched (§scope-discipline;
  the §phase-1d gate verifies the committed diff is a subset of this)
- `resolve_intent_excerpt`: 1–3 sentences refine needs for item-2
- `cited_rdrs`, `followup_katas`: list or empty
- `verdict`: `ok` | `stopped:<reason>`

### 1d. Verify

Per §phase-1d-verify-shared with `FILES_MAX=10`,
`DELETIONS_MAX=300`. Scope gate is a parent-side floor against
runaway resolve agents; kata-resolve step 6's own pre-commit
check is the primary gate. The shared §phase-1d in-scope-set check
also fires here: every committed path must be a member of the
agent's reported `in_scope_paths`, else trip (catches the
small-unrelated-edit case the count floor misses — the 2tx8
test-weakening mode).

Plus one kata-specific check:
```sh
kata show <id> --json | jq -r .issue.owner          # == $SESSION_ID
```

Record `followup_katas` + `resolve_intent_excerpt` for phase 2.

**Exception: `verdict: stopped:needs-triage:*`.** Worktree is
empty by contract; not a `--resume` candidate. Parent cleanup,
in order:
1. `git worktree remove .claude/worktrees/<SHORT_ID>` (empty by
   contract; no `--force` needed).
2. `git branch -d worktree-<SHORT_ID>` (no commits, points at
   `TARGET_BRANCH`).
3. `kata unassign <id>`.
4. `kata label rm <id> lifecycle:resolving`.

Then, with the worktree torn down, route the kata into
`/kata-scope-review <id> --confirm` (read-only on git). This does the
source-grounding the resolve agent declined and forces a verdict that
lands a **durable** inbox label — `lifecycle:reviewed` with a corrected
plan (→ re-ship), or `kind:rdr-seed`, or `inbox:hold` / `inbox:needs-review`
— carrying the agent's phrase + `resolve_intent_excerpt` as the review's
seed. `--confirm` keeps the human gate. This converts the last ephemeral
ship-time stop into a durable inbox label (see ship-flow-state-machine reference
§4.8 / §5.4 and the existing 'proposed' note); the verdict, not an
AskUserQuestion answer, decides the next move.

**Exception: `verdict: stopped:worktree-isolation-failed`** —
same teardown as `needs-triage` (no edits made). Not a `--resume`
candidate.

## Phase 2 — Rebase + Refine

Per §phase-2-rebase-refine. Single agent owns both rebase and
refine.

### 2a. Label transition (parent)

```sh
kata label add <id> lifecycle:refining --json     # phase-2 marker
kata label rm  <id> lifecycle:resolving --json
kata comment   <id> --body "ship session $SESSION_ID — phase 2 starting" --json
```

### 2b. Spawn rebase+refine agent (leaf — §leaf-agent-contract)

Brief follows §phase-2-rebase-refine, with kata specializations:

- Kata id, `$SESSION_ID`, `worktree_path`, branch.
- **`PRIMARY_ROOT`** + **`KATA_FLIGHT_CONTEXT_ROOT`** (absolute, from Coordination;
  agents may also resolve it from the workspace marker — `WS=$(dirname
  "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")`;
  `KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
  Refine grounds findings against the RDR + critiques + guidelines
  roborev never saw; the consumer worktree has none of these, so read
  them from `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...` and `$KATA_FLIGHT_CONTEXT_ROOT/context/...`
  (the configured RDR evidence root, not the external RDR methodology repo).
- `resolve_intent_excerpt` + `cited_rdrs` from phase 1.
- §tiebreakers-shared verbatim plus kata-ship `TIEBREAKER_4`
  (`KATA_PUSH:` packet — see above) and `TIEBREAKER_5`.
- **Ultrathink before applying** HIGH / cross-subsystem /
  structural / `project_core_principles`-touching /
  intent-conflicting fixes.
- Tiebreaker 1–2 → auto-dispose per §Mechanic (no user ask).
  Confirmed FP → agent runs `/roborev-respond` + dismiss + re-enter
  loop, citing the refuting grounding. Real → continue.
- Step 1 (rebase) and Step 2 (refine `--max-iterations 5`) per
  §phase-2-rebase-refine. **Scope refine to the kata's OWN committed
  diff** — the resolve/refine commits, i.e. the post-rebase range
  `$TARGET_BRANCH..HEAD` narrowed to *this kata's* commits, **not** a
  bare `main..HEAD` over whatever else rode the rebase. Pass refine its
  `--since` as the kata's first commit's parent so its verdict + test
  *selection* cover only the kata's diff. This keeps the verdict
  **rebase-stable** (a rebase that replays unrelated trunk commits no
  longer re-opens it — corpus: a rebase discarded 11 commits once and
  re-ran the full ~42s suite 13x). Reserve the full `go test ./...`
  suite for the final pre-merge gate (Phase 3), not per refine
  iteration.
- **Scope alarm**: a finding against files OTHER than this kata's
  commits is out-of-scope → `TIEBREAKER_4` (auto-disposed: push to a
  sibling kata or drop with grounding, no user ask).
- **No unrecorded dismissals** at any severity — each carries its
  grounding.

**Report schema** (≤200 words; per §phase-2-rebase-refine plus
kata-ship additions):

Standard fields plus:
- `pushed_to_kata`: `<severity> <source-anchor> → <short_id>
  (existing|new)` per push (empty if none) — parent verifies the
  `roborev` label landed

### 2c. Gate + worktree re-verify

Per §phase-2-rebase-refine gate. Same outcomes.

### 2d. Broadening after `flapping`

Per §phase-2-broadening.

## Phase 3 — Ship

Per §phase-3-ship-agent. Single agent owns the entire phase.
Parent only does label transitions and the final `kata close`.

### 3a. Label transition (parent)

```sh
kata label add <id> lifecycle:shipping --json     # phase-3 marker
kata label rm  <id> lifecycle:refining --json
```

### 3b. Spawn ship agent (leaf — §leaf-agent-contract)

Brief follows §phase-3-ship-agent, with kata specializations:

- Kata id, `$SESSION_ID`, `worktree_path`, branch, primary
  `MAIN_WT`, `TARGET_BRANCH`.
- `commits_added` list from phase 2.
- §tiebreakers-shared verbatim (tiebreaker 4 won't fire in ship).

Steps 1–6 of §phase-3-ship-agent unchanged. §squash-rules
applies; the original-intent commit is the kata-resolve commit
(its subsystem prefix becomes the squash subject's
`<subsystem>`).

### 3c. Close kata (parent)

```sh
kata label rm  <id> lifecycle:shipping --json
kata unassign  <id>                    --json
kata close     <id> --done --commit <merged_sha> \
  --message "Shipped on $TARGET_BRANCH: <scope + how verified — ≥40 chars>" --json
```

`kata close` **asserts completion** — it requires a substantive `--message`
(≥40 chars: scope + verification) **and** typed `--evidence`. Use the
`--commit <sha>` sugar (= `--evidence commit:<sha>`); `--done` is sugar for
`--reason done`. A bare `kata close <id> --reason done` **fails validation**
(the comment is folded into `--message`, so the prior `kata comment` line is
dropped — `--message` is the close's substantive record).

Order load-bearing: labels → unassign → close.

**Read-back-verify the close.** `kata close` can exit 0 without
persisting; after it, re-read and confirm `status == "closed" &&
owner == null` (don't trust the exit). Likewise after any
state-changing `kata label add` / transition above, re-read the
top-level `.labels[]` (§gate-4 caution: objects on show, never
`.issue.labels`) to confirm the label actually landed — `kata label
add` can return ok without persisting (corpus: m3sd). Re-issue on
mismatch.

## Auto mode

`/kata-ship 42 81 117`: ship in order, complete each before next.
Non-tiebreaker stop → surface + continue. Finding-tiebreaker (1/2/4) →
auto-dispose + continue. Stop-tiebreaker (3/5) → pause + ask + resume.

Fresh agent per kata per phase. Parent per-kata budget ~5k
tokens (reports + lock commands).

## Resume

Per §resume-mechanics, with kata-ship specializations:

`--resume <id>` adopts a ship-owned kata.

1. **Ownership check.** `kata show --json`: owner matches
   `kata-ship/*`. Non-ship-owned → refused.
2. **Locate worktree** via `git worktree list` looking for branch
   `worktree-<SHORT_ID>`. Worktree gone but branch exists →
   re-attach via raw git (parent, state-mutating but
   worktree-only):
   ```sh
   git worktree add .claude/worktrees/<SHORT_ID> worktree-<SHORT_ID>
   ```
   Both gone → refuse.
3. **Mint fresh `$SESSION_ID`**, `kata claim <id> --as "$SESSION_ID"
   --force` (deliberate retake — step 1 already proved `kata-ship/*`
   ownership; `--force` is the only sanctioned overwrite), leave phase
   label intact, post resume comment, continue at that phase with a fresh
   agent (each phase's brief reads prior phase's comment).
4. **Re-run §phase-1d-verify-shared** against the existing tip
   (including the scope gate) before resuming Phase 2 — a
   runaway commit from the prior session does not get amnestied
   by resume.

## Releasing a stuck kata (manual)

```sh
kata unassign  <id>                       --json
kata label rm  <id> lifecycle:resolving   --json   # or lifecycle:refining / lifecycle:shipping
```

## Failure recovery (consumer rows; shared rows in §failure-recovery-shared)

Most failures leave kata open, owner + phase label + worktree
intact. The `needs-triage` row is the exception — parent clears
owner + label, then routes the kata into `/kata-scope-review
<id> --confirm` so the stop lands a durable inbox label instead of
an ephemeral prompt.

| Failure | Action |
|---|---|
| Gate 4 (`kind:rdr-seed` label) | Refuse with `stopped:rdr-seed`; surface that the deliverable is an RDR draft (umbrella kata dtr1) and human direction is required (slot allocation, design-question resolution, or upstream RDR lock). |
| Gate 5 (owned/labeled) | Refuse + surface owner/label. |
| Lost claim race (`kata claim` exit 5 / `already_claimed`) | Refuse + exit. The claim never took ownership — **nothing to release** (no `unassign`, no `label rm`); another session legitimately owns it. |
| Kata blocked | Refuse. |
| Phase-1b worktree creation fail | Per §failure-recovery-shared, plus `kata unassign` + `kata label rm lifecycle:resolving`. Not `--resume`. |
| `--prepared` precondition fail | Refuse with `stopped:prepared:<owner-not-kata-ship\|missing-phase-label\|worktree-missing\|worktree-path-missing>`. Do not mutate kata or worktree state — the caller (parent of the sub-agent) is responsible for cleanup. |
| Resolve `stopped:worktree-isolation-failed` | Sub-agent failed its `cd <worktree_path>` or post-cd verify (no edits made). Same teardown as `needs-triage`: remove worktree + branch + unassign + label rm. Not `--resume`. |
| Resolve `stopped:needs-triage:*` | Worktree empty by contract. `git worktree remove .claude/worktrees/<SHORT_ID>` + `git branch -d worktree-<SHORT_ID>` + `kata unassign` + `kata label rm lifecycle:resolving`; then route into `/kata-scope-review <id> --confirm` (carries phrase + `resolve_intent_excerpt`) — lands a durable label (`lifecycle:reviewed` / `kind:rdr-seed` / `inbox:hold` / `inbox:needs-review`), not an ephemeral prompt. Not `--resume`. |
| `TIEBREAKER_4` (out-of-scope finding) | Auto-disposed (no ask). `KATA_PUSH:` packet → parent `kata create` + `kata label add src:roborev` + `kata label add severity:<l/m/h>` → agent `/roborev-respond` cites kata. |
| `TIEBREAKER_5` (multi-issue auto mode) | A *stop* tiebreaker (3) fires → pause that issue, ask, continue. 1/2/4 auto-dispose without pausing. |

All other rows (refine flapping, rebase conflict `rerere` can't
clear, ff-only rejected twice, Phase-3 `stopped:test_lint_fail`,
squash `fell_back`, daemon_unhealthy, …) → §failure-recovery-shared.

## See also

- `worktree-ship-pipeline` — shared bones; **read first**.
- `/kata-resolve` (`--no-lock-mgmt` from phase 1c, invoked inside
  the pre-created worktree; skill detects pre-existing isolation
  and skips its own worktree-creation step)
- `/prompt-ship` — sibling consumer; prompt-driven.
- `/roborev-refine` (phase 2)
- `/kata-scope-review` (Phase-1d `needs-triage` route — source-grounds
  the declined kata and lands a durable inbox label)
- `/roborev-respond` (dismiss after tiebreaker)
- `git worktree add` (raw Bash, no `EnterWorktree`) — parent-only,
  phase 1b (§phase-1b-worktree-creation). Sub-agents `cd
  <worktree_path>` instead.
