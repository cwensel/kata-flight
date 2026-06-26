---
name: kata-inbox
description: 'Use to drain human-owned kata inbox states (`inbox:hold` and `inbox:needs-review`). Grounds each item, recommends a disposition, asks the human to choose/approve, then applies tracker-only state transitions. Trigger for review/unblock/clear/triage held or needs-review katas.'
---

# kata-inbox

Drain `inbox:*` kata states in the same style that `rdr-seed-triage` drains
`kind:rdr-seed`. The invariant is simple: any open kata excluded from flight must
name the skill that owns its next move.

- `lifecycle:reviewed` -> `/kata-flight`
- `kind:rdr-seed` -> `/rdr-seed-triage`
- `inbox:hold` / `inbox:needs-review` -> `/kata-inbox`

This skill mutates only the kata tracker. It never edits code, creates a
worktree, or commits. It grounds enough source/context to make a recommendation,
then asks the human to choose a legal disposition before acting.

## Usage

```
/kata-inbox <short-id> [<short-id> ...]
/kata-inbox --label inbox:hold
/kata-inbox --label inbox:needs-review
/kata-inbox --all
/kata-inbox --confirm
```

No arguments -> print Usage and stop. `--all` is the explicit whole-inbox selector
(`inbox:hold` plus `inbox:needs-review`). Multiple selectors union and dedupe. A
selector resolving empty -> refuse.

## Posture

- **Human-gated by default.** Always present the issue summary, current inbox
  reason, grounding, and recommended disposition before mutation. The human must
  approve or choose another disposition. `--confirm` is mandatory before close,
  parent closure, bulk split creation, or other destructive/fan-out actions.
- **Orchestrator is the single writer.** Sub-agents may ground one kata and
  propose a disposition, but this skill applies all label/link/comment/close
  changes from the parent session.
- **Conservative bias.** If evidence is weak, keep the kata open and either
  `KEEP-HELD` or `RESCOPE`; never close or silently clear an inbox label.
- **Exactly one terminal disposition per kata.** Record it in the report and in a
  kata comment.

## Verdict taxonomy

| Verdict | Meaning | Route |
|---|---|---|
| `READY` | The hold/review concern is resolved; the kata is flight-shippable with an embedded plan. | clear `inbox:*`, add `lifecycle:reviewed`, comment `reviewed-at:<HEAD>` |
| `KEEP-HELD` | The blocker/parking reason is still valid or intentionally deferred. | keep/add `inbox:hold`, comment `held-at:<YYYY-MM-DD>` |
| `RESCOPE` | The inbox item is real but needs a corrected problem statement/plan before shipping. | clear `inbox:*`, comment/body/title update, then `lifecycle:reviewed` or `inbox:hold` depending on readiness |
| `SPLIT` | The kata bundles multiple independently shippable or reviewable units. | create/reparent children; parent stays `inbox:hold` unless explicitly closed |
| `TO-SEED` | The item is actually a design fork, not an inbox hold. | clear `inbox:*`, add `kind:rdr-seed`, comment the fork |
| `CLOSE` | The work is duplicate, superseded, adjudicated, or otherwise no longer valid. | dependent guard, then `kata close` with typed evidence |
| `REHOME` | The issue is valid but assigned to the wrong parent/batch/label lane. | parent/batch/label cleanup; optionally combine with another verdict |

`REHOME` may be paired with `READY`, `KEEP-HELD`, or `TO-SEED`; it is listed as a
separate action because transcript history shows it is a common inbox task.

## Phase 0 - Locate & resolve

Use the same worktree-safe root derivation as `kata-scope-review`:

```sh
PRIMARY_ROOT=$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")
[ -f "$PRIMARY_ROOT/.kata-flight/env" ] && . "$PRIMARY_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$PRIMARY_ROOT")}"
[ "$(basename "$PRIMARY_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$PRIMARY_ROOT" >&2; exit 1; }
WS=$(dirname "$PRIMARY_ROOT")
KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
[ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
```

Resolve candidates:

1. Explicit ids -> trust, but verify open status and labels.
2. `--label X` -> `kata list --status open --json`, filter `.issues[].labels[]`
   for `X` (bare strings on list output).
3. `--all` -> open katas carrying `inbox:hold` or `inbox:needs-review`.

Skip owned katas unless the owner is the current human and the user explicitly
named the id. Skip `kind:rdr-seed` unless it also carries `inbox:*`; if both are
present, the recommended disposition is usually `TO-SEED` cleanup or
`KEEP-HELD` with a comment explaining why it is not ready for `rdr-seed-triage`.

## Phase 1 - Summarize

For each candidate, read `kata show <id> --json` and summarize:

- title, status, owner, priority
- labels, especially all `inbox:*`, `kind:*`, `lifecycle:*`, `batch:*`, `area:*`
- parent/child/blocking links
- latest `held-at:`, `reviewed-at:`, `seed-triaged:`, and relevant inbox comments
- why the item entered inbox, in one or two lines

Also run cheap grounding for likely stale holds:

- grep named code symbols/files from the kata body/comments
- check referenced parent/umbrella children for open/closed status
- check referenced RDR status when the hold cites an RDR or design decision
- compare current labels/batches/parents to the stated parking reason

For batches larger than 3, use one sub-agent per kata only for the grounding
summary and proposed verdict. Sub-agents must output verdict blocks only and make
no mutations.

## Phase 2 - Recommend & ask

Present a compact decision table before acting:

```
kata-inbox: <selector>  items: N

<id> - <title>
state: <inbox labels> since <held-at/comment date if known>
reason: <why it is in inbox>
grounding: <current evidence, one paragraph max>
recommendation: <VERDICT> - <why>
actions: <labels/comments/links/closes that would happen>
```

Ask the human to approve the recommended verdicts or choose alternatives. Do not
ask an open-ended question when the valid state-machine moves are known. For a
single kata, ask one direct question ("Proceed with READY for p6mf?"). For a
batch, ask one row per kata.

If the harness lacks a structured AskUserQuestion tool, stop after the decision
table and ask the user for the chosen disposition(s). Do not mutate until the
human answers.

## Phase 3 - Apply

Before every mutation, re-read `kata show` / `kata list` for the row being
changed; do not act on stale state.

### READY

1. Comment with `reviewed-at: <HEAD-sha>` first line, followed by the confirmed
   plan and the inbox-unblock rationale.
2. Remove every `inbox:*` label.
3. Add `lifecycle:reviewed`.
4. Strip `batch:*` only if the kata no longer fits the batch. Otherwise leave
   the standing batch so `/kata-flight --label <batch>` can pick it up.

### KEEP-HELD

1. Comment with first line `held-at: <YYYY-MM-DD>` using the harness current
   date, not wall-clock shell time.
2. Ensure `inbox:hold` is present.
3. Remove `inbox:needs-review` only if the human chose a known parked state
   rather than an unresolved decision.
4. Strip `lifecycle:reviewed` and `batch:*` if the kata is not flight-drainable.

### RESCOPE

1. Comment or edit the body/title with the corrected scope and plan.
2. If now shippable, perform `READY`.
3. If still parked, perform `KEEP-HELD`.
4. If it is a design fork, perform `TO-SEED`.

### SPLIT

Under `--confirm`, create child katas for each named unit, carrying appropriate
`area:*`, `severity:*`, and provenance labels. Parent handling:

- parent remains `inbox:hold` with a `held-at:` comment until children exist and
  links are correct;
- close the parent only when the human explicitly chose close and
  the dependent guard passes.

### TO-SEED

1. Comment the load-bearing design fork.
2. Add `kind:rdr-seed`.
3. Remove every `inbox:*`.
4. Strip `lifecycle:reviewed` and `batch:*` unless the batch is deliberately
   tracking the seed as visible but non-flight-shippable.

### CLOSE

Run the dependent guard first. If the kata blocks open dependents, either re-point
them to the replacement/survivor or stop and ask; never strand a dependent.

Then close with typed evidence:

```sh
kata close <id> --reason <done|wontfix|duplicate|superseded|audit-no-change> \
  --message "<substantive message>" \
  --evidence "<typed-evidence>"
```

Pace sibling closes to respect the kata close throttle. After close, verify
`status == closed`, owner clear, and no active lifecycle labels.

Dependent guard means reading top-level `.links[]` from `kata show <id> --json`
and checking `type=="blocks"` edges where this kata is the blocker and the
dependent is still open. For merge/duplicate closes, re-point dependents to the
survivor. For no-replacement closes, stop and ask unless the human already
approved removing or re-pointing the relationship.

### REHOME

Use `kata edit` and `kata label` to fix parent, batch, area, severity, or title.
If removing the last open child from an umbrella, check whether the old umbrella
now has zero open children; only close it under `--confirm` and after reading its
children.

## Phase 4 - Verify & report

Read back every changed issue. Report from actual state, not command success.
Write a scratch report at:

```
$KATA_FLIGHT_CONTEXT_ROOT/_scope-review/kata-inbox-<selector-slug>.md
```

Report format:

```
kata-inbox: <selector>  items: N
  ready:      <id> ...
  held:       <id> ...
  rescoped:   <id> ...
  split:      <parent>-><child>+<child> ...
  to-seed:    <id> ...
  closed:     <id>=<reason> ...
  rehomed:    <id> ...
  surfaced:   <id> ... (needed human answer / dependent guard / ambiguity)
  next: /kata-flight --label <X> | /rdr-seed-triage <id> | none
```

## Failure modes

| Condition | Action |
|---|---|
| No selector | Print Usage and stop. |
| Selector resolves no open inbox items | Refuse with a short explanation. |
| Human declines all recommended moves | Leave state unchanged; comment only if explicitly requested. |
| Evidence cannot settle stale hold | `KEEP-HELD` with a refreshed `held-at:` rationale. |
| Close would strand dependents | Stop or re-point with explicit human approval. |
| A kata has both `inbox:*` and `kind:rdr-seed` | Prefer cleanup to one owner; usually `TO-SEED` or `KEEP-HELD` with reason. |
| Label/link command exits 0 but state did not change | Treat read-back as authoritative; retry once, then surface. |

## See also

- `kata-flow-ops` - observes inbox depth; this skill acts on `inbox:*`.
- `kata-scope-review` - fills `inbox:*` when a flight gate needs human review.
- `rdr-seed-triage` - same drain pattern for `kind:rdr-seed`; do not merge the
  two, because `kind:rdr-seed` has RDR-specific shape rules.
- `kata-flight` - excludes held/routed items from shipping and resumes once this
  skill clears them to `lifecycle:reviewed`.
