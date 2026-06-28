# Kata Flight Label Vocabulary

This is the generic label model the Kata Flight skills assume. A consumer
project may override or extend it in
`$KATA_FLIGHT_CONTEXT_ROOT/context/label-vocabulary.md`.

## Lifecycle

Use at most one `lifecycle:*` label per open kata.

- `lifecycle:queued` — reviewed or selected work waiting to ship.
- `lifecycle:reviewed` — scope-reviewed and ready for a flight.
- `lifecycle:resolving` — currently in the resolve phase.
- `lifecycle:refining` — currently in the roborev refine phase.
- `lifecycle:shipping` — currently in the landing/close phase.

An open kata with no `lifecycle:*` label is treated as filed/unreviewed.

## Inbox

- `inbox:needs-review` — human review required before shipping.
- `inbox:hold` — intentionally parked.
- `kind:rdr-seed` — design-shaped work that should enter the RDR flow.
- `kind:rdr-tracked` — a kata tracking an RDR implementation.

Ownership rule: `inbox:needs-review` and `inbox:hold` are drained by
`kata-inbox`; `kind:rdr-seed` is drained by `rdr-seed-triage`. Do not leave an
open kata excluded from flight without a label that names its owning drain.

## Batch And Provenance

- `batch:<name>` — temporary grouping for a flight or RDR implementation run.
- `src:roborev` — generated from a roborev finding.
- `severity:<low|medium|high>` — impact bucket used when creating follow-up work.
- `area:<name>` — consumer-defined subsystem area.
- `type:<name>` — consumer-defined work type, such as `type:bug`.

## Stop reasons

Canonical flight-level `stopped:<reason>` tokens — the buckets that reach the
`flight:stopped:*` comment surface. Used to query stops without scraping prose.
(Skills emit further internal exit-prefixes; this lists the flight outcomes.)

- `wrong-repo` — ran against the wrong repo.
- `context-root-not-found` — `$KATA_FLIGHT_CONTEXT_ROOT` unresolved.
- `repo-anchor-drift` — repo anchor moved mid-flight.
- `lost-claim-race` — another worker claimed the kata first.
- `worktree-prep-failed` — worktree setup failed.
- `worktree-isolation-failed` — worktree leaked the primary path.
- `worktree-live` — a linked worktree already exists on the kata's branch (a
  live/concurrent ship); surfaced by §preflight-classifier, never reclaimed.
- `primary-dirty` — primary checkout had uncommitted changes before claiming.
- `primary-off-branch` — primary checkout was not on `TARGET_BRANCH`.
- `prepared-precondition-failed` — `--prepared` precondition unmet.
- `not-shipped` — verification missed, not resumable.
- `not-shipped-after-resume` — still unshipped after one resume.
- `needs-triage` — work needs human triage before shipping.
- `permission-boundary` — an external/parent-owned write was denied past the
  one-retry bound (§external-op-classification).
- `daemon-unreachable` — kata/roborev daemon could not be reached or bound.

## Reclaimable reasons

`reclaimable:<reason>` codes are emitted by §preflight-classifier for worktree
debris that is recoverable by an offered action (distinct from `stopped:*`,
which refuses/halts). They do not reach the `flight:stopped:*` surface; they
drive an `AskUserQuestion`/cleanup, then the flight proceeds.

- `dead-lock` — branch + path both present with no linked worktree (crashed
  session); the §Stale-lock reclaim (rja8) case caught at git level.
- `branch-only` — branch exists, path absent: a `--resume` re-attach candidate,
  or a stale branch to clean up.
- `path-only` — stale worktree directory with no matching branch.

Consumers may extend this set via the override path noted at the top of this file.
