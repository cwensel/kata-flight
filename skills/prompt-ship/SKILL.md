---
name: prompt-ship
argument-hint: <prompt-path | inline body> | --resume <branch>
description: 'Use to run a free-form prompt through the shared worktree ship pipeline without creating kata issues. Accepts a prompt path or inline body. Trigger for ship this prompt or $prompt-ship.'
---

# prompt-ship

Consumer of `worktree-ship-pipeline`. **Read that file first** —
this skill specializes the work source, identity, lock, and close
step. Every section cited as `§<anchor>` below refers to
`worktree-ship-pipeline` SKILL.md.

## Usage

```
/prompt-ship <path/to/prompt.md>
/prompt-ship <inline prompt body — multi-line, @-file refs ok>
/prompt-ship --resume <branch>
```

**Input resolution.** Strip leading whitespace; take the first
whitespace-separated token. If `[ -r "$token" ]`, prompt =
file contents. Otherwise prompt = entire argument verbatim
(including newlines). Empty resolved prompt → refuse
`stopped:no-prompt`.

No args → refuse with `stopped:no-prompt`. No auto-pick — without a
prompt there is nothing to ship.

## Parameters (consumed by worktree-ship-pipeline)

| Parameter | Value |
|---|---|
| `EXPECTED_REPO_BASENAME` | `consumer-repo` (§repo-anchor) |
| `WORK_SOURCE` | Verbatim user prompt (file contents or inline body) |
| `SHORT_ID` | `$(uuidgen | tr A-Z a-z | cut -c1-8)` |
| `BRANCH` | `worktree-prompt-<SHORT_ID>` |
| `WORKTREE_PATH` | `.claude/worktrees/prompt-<SHORT_ID>` |
| `TARGET_BRANCH` | `$(git branch --show-current)` captured at preflight |
| `INTENT_FIELD` | `intent_excerpt` |
| `FILES_MAX` | `20` |
| `DELETIONS_MAX` | `600` |
| `TIEBREAKER_4` | Ask user `fix-now` / `defer` / `false-positive` (see below) |
| `TIEBREAKER_5` | n/a (one prompt per invocation) |
| `LOCK_ANCHOR` | Branch existence + `<WORKTREE_PATH>/.run-prompt/PROMPT.md` |
| `CLOSE_STEP` | Echo `merged_sha` + `summary` to user |

The worktree is created per §phase-1b-worktree-creation with name
`prompt-<SHORT_ID>`; the resulting branch is `worktree-prompt-<SHORT_ID>`.

Looser scope thresholds than `/kata-ship` (10/300) because
free-form prompts legitimately span more surface than a single kata.

## TIEBREAKER_4 (out-of-scope finding)

**prompt-ship re-gates 1/2/4** (the §tiebreakers-shared opt-out): a
free-form prompt has no RDR/kata scope to ground an auto-disposition
against, so finding tiebreakers ask the user here rather than
auto-dispose. (kata-flight does not invoke prompt-ship.)

Agent returns a packet (≤80 words) per §tiebreakers-shared Mechanic:
roborev `<severity> <file:line>` cite, one-sentence rationale for why
it's out of scope vs the prompt. The continuation agent (or the
messaged agent, fast-path) applies the user's answer:

- `fix-now` → agent applies inline (counts toward `commits_added`).
- `defer` → agent runs `/roborev-respond` citing the user's
  deferral rationale verbatim.
- `false-positive` → agent runs `/roborev-respond` + dismiss.

No kata / issue tracker write. No `FOLLOWUPS.md` or other in-repo
debt file.

## Phase 1 — Acquire + Execute

### 1a. Mint identity

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"   # §repo-anchor
[ -f "$REPO_ROOT/.kata-flight/env" ] && . "$REPO_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$REPO_ROOT")}"
[ "$(basename "$REPO_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$REPO_ROOT" >&2; exit 1; }
SHORT_ID=$(uuidgen | tr A-Z a-z | cut -c1-8)
SESSION_ID="prompt-ship/$SHORT_ID"
BRANCH="worktree-prompt-$SHORT_ID"
WORKTREE_PATH="$REPO_ROOT/.claude/worktrees/prompt-$SHORT_ID"   # absolute, anchored
TARGET_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
PRIMARY_ROOT="$REPO_ROOT"            # == REPO_ROOT in valid parent state
WS="$(dirname "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")"   # workspace root (worktree-invariant)
KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
if   [ -f "$PRIMARY_ROOT/.kata-flight/workspace" ]; then . "$PRIMARY_ROOT/.kata-flight/workspace"; elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"; fi
[ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
```

The conventions and critiques resources live in the configured Kata Flight context root
repo, derived as `$KATA_FLIGHT_CONTEXT_ROOT` (the primary checkout's sibling), so they
are tracked and resolve regardless of the worktree. Every sub-agent
brief passes `$KATA_FLIGHT_CONTEXT_ROOT` (and `$PRIMARY_ROOT` for the work tree) so the
agent reads conventions (`$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md`)
and, when the prompt touches RDR-governed code, the governing RDR +
critiques (`$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`) by absolute path. Use the configured
`rdr/evidence/`, not the external RDR methodology repo. This is
symlink-safe because `KATA_FLIGHT_CONTEXT_ROOT` derives from the worktree's git
topology, not the skill file location.

If `git worktree list --porcelain` already shows that branch
(uuid collision, extremely rare), re-roll.

### 1b. Parent creates the worktree

Per §phase-1b-worktree-creation, with `name: "prompt-<SHORT_ID>"`.

**Additional step after verify (4) and before recording (5):**
persist the prompt for resume. Parent writes the resolved prompt
to `<WORKTREE_PATH>/.run-prompt/PROMPT.md` using the **Write tool**
(preserves newlines).

The repo root `.gitignore` already excludes `.claude/`, so
`.run-prompt/PROMPT.md` is invisible to git from every angle.
**Do not touch `.git/info/exclude`** — see §phase-1b-worktree-creation
final paragraph for the reason.

### 1c. Spawn execute agent

`Agent(subagent_type: "general-purpose")`. Brief:

- `$SESSION_ID`, parent cwd, `worktree_path`, `branch`,
  `TARGET_BRANCH`.
- **`PRIMARY_ROOT`** + **`KATA_FLIGHT_CONTEXT_ROOT`** (absolute, from 1a). Resources
  live in the configured Kata Flight context root; the agent reads conventions from
  `$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md`, and when the prompt
  touches code an RDR governs, grounds against that RDR + its critiques
  at `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...` (the configured RDR evidence root, not the
  external RDR methodology repo).
- **Gauge complexity; ultrathink if non-trivial.** Trivial paths
  (typo, hint phrasing, mechanical rename) proceed directly. Otherwise
  ultrathink before editing and read cited code + any governing RDR +
  principles first. Triggers: cross-subsystem reach, structural change
  (new abstraction, audit-boundary move), a finding/edit touching
  `project_core_principles`, or round-trip/closure/hash-stability
  invariants where a wrong call corrupts artifacts silently.
- **First Bash call:** `cd <worktree_path>` + isolation verify:
  ```sh
  [ "$(pwd -P)" = "<worktree_path>" ]
  [ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]
  [ "$(git branch --show-current)" = "worktree-prompt-<SHORT_ID>" ]
  ```
  Any failure → return `stopped:worktree-isolation-failed`; do not
  edit any file.
- **§worktree-invariant verbatim.**
- **§scope-discipline verbatim.** Commit ONLY the paths the prompt
  names plus the callers/tests they force; never weaken/clean up an
  unrelated test or source to make a broad `go test ./...` pass;
  report the final set as `in_scope_paths`. (A free-form prompt may
  legitimately span more surface than a kata — `FILES_MAX=20` reflects
  that — but "more files the prompt asks for" is not "unrelated files
  cleaned up on the side.")
- §tiebreakers-shared verbatim, plus the prompt-ship `TIEBREAKER_4`
  spec from above.
- **The verbatim user prompt** between explicit delimiters
  (`<<<PROMPT` ... `PROMPT>>>`), preceded by: *"The following is
  the user's request, verbatim. Execute it inside the worktree.
  File paths and @-mentions in the prompt are relative to the
  primary repo root; the worktree mirrors that tree."*
- Project commit conventions: Conventional Commits
  (`feat|fix|chore(<scope>): <outcome>`); **no LLM attribution**
  in subjects/bodies/co-authors; **no roborev IDs / kata slugs /
  `job NNN` / bare 4-char slugs** in commit subjects (memory
  `commit_subject_self_check`); run `golangci-lint run` on changed
  scope before committing (memory `lint_before_commit`).
- Tiebreaker protocol: return a `TIEBREAKER:` packet (condition #,
  ≤80-word context, proposed disposition) per §tiebreakers-shared
  Mechanic.

**Report schema** (≤200 words, no diffs):

- `worktree_path`, `branch`, `head_sha` (short)
- `commit_subject`
- `in_scope_paths`: every path the commit(s) touched (§scope-discipline;
  the §phase-1d gate verifies the committed diff is a subset of this)
- `intent_excerpt`: 1–3 sentences — refine's tiebreaker-2 context
- `cited_refs`: RDRs / docs / files (or empty)
- `followups_noted`: optional informational TODOs (no issue
  tracker write happens)
- `verdict`: `ok` | `stopped:<reason>`

### 1d. Verify

Per §phase-1d-verify-shared with `FILES_MAX=20`,
`DELETIONS_MAX=600`. Scope-gate trip → surface shortstat to user;
user answers `proceed` (refine anyway) or `abort` (`git worktree
remove` + `git branch -d`). The shared §phase-1d in-scope-set check
also fires: any committed path outside the agent's reported
`in_scope_paths` trips the same `proceed`/`abort` question.

`stopped:worktree-isolation-failed` or `stopped:empty-result`
(no commits) → empty by contract. Teardown:
```sh
git worktree remove <WORKTREE_PATH>
git branch -d <BRANCH>
```
Not a `--resume` candidate. For `empty-result`, the prompt itself
may need editing; user re-invokes with a revised prompt.

## Phase 2 — Rebase + Refine

Per §phase-2-rebase-refine. No consumer lock/label transition
(branch existence is the lock).

Brief includes:
- The verbatim user prompt (refine's tiebreaker-2 needs it).
- **`PRIMARY_ROOT`** + **`KATA_FLIGHT_CONTEXT_ROOT`** (absolute, from 1a) per
  §phase-2-rebase-refine's grounding bullet — the agent grounds findings
  against any governing RDR + critiques (`$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`)
  and conventions (`$KATA_FLIGHT_CONTEXT_ROOT/context/...`) before fixing.
  §tiebreakers-shared
  (included verbatim by §phase-2-rebase-refine) already carries the
  ultrathink-before-applying rule.
- `intent_excerpt` + `cited_refs` from Phase 1.
- Prompt-ship `TIEBREAKER_4` spec verbatim.

Flapping → §phase-2-broadening.

## Phase 3 — Ship

Per §phase-3-ship-agent. After ff-merge + teardown:

**Close step (consumer-defined):** echo `merged_sha` + `summary`
from the ship report. No external ticket to close.

## Resume

Per §resume-mechanics, with prompt-ship specializations:

1. **Ownership check.** Branch must match `worktree-prompt-*` and
   the worktree (or `.run-prompt/PROMPT.md` after re-attach) must
   exist. No cross-consumer adoption.
2. **Locate worktree.** Standard `git worktree list` lookup;
   `git worktree add <WORKTREE_PATH> <BRANCH>` to re-attach if the
   branch exists but worktree is gone. Both gone → refuse
   `stopped:resume-target-missing`.
3. **Read persisted intent.** `<WORKTREE_PATH>/.run-prompt/PROMPT.md`
   must exist and be non-empty. Missing → refuse
   `stopped:resume-prompt-missing`.
4. **Mint fresh `$SESSION_ID`** (`prompt-ship/<new-uuid>`).
   `$SHORT_ID` from the branch stays as identity.
5. Determine phase by tip state per §resume-mechanics.
6. Re-run §phase-1d-verify-shared (including scope gate) against
   the existing tip before resuming Phase 2.

## Manual release

```sh
git worktree remove .claude/worktrees/prompt-<SHORT_ID>
git branch -D worktree-prompt-<SHORT_ID>
```

No external state to clean.

## Failure recovery (consumer rows; shared rows in §failure-recovery-shared)

| Failure | Action |
|---|---|
| Empty/unreadable prompt | Refuse `stopped:no-prompt` / `stopped:empty-prompt`. |
| Phase-1d scope gate trips | Surface shortstat → `proceed` or `abort`. |
| `TIEBREAKER_4` | Agent returns packet → parent asks `fix-now`/`defer`/`false-positive` → respawn continuation (§Mechanic). |
| `stopped:resume-prompt-missing` | Persisted intent gone; user must re-invoke fresh or recreate PROMPT.md before retrying. |

All other rows → §failure-recovery-shared.

## See also

- `worktree-ship-pipeline` — shared bones; **read first**.
- `/kata-ship` — sibling consumer; kata-driven.
- `/roborev-refine` (Phase 2)
- `/roborev-respond` (dismiss after tiebreaker)
