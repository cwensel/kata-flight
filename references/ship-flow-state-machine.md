# Kata Flight Ship-Flow State Machine

This is the generic state machine the Kata Flight skills assume. A consumer
project may override or extend it in
`$KATA_FLIGHT_CONTEXT_ROOT/context/ship-flow-state-machine.md`.

## Dashboard

The read-only dashboard groups open katas by:

- filed: no `lifecycle:*` label
- queued: `lifecycle:queued`
- reviewed: `lifecycle:reviewed`
- resolving: `lifecycle:resolving`
- refining: `lifecycle:refining`
- shipping: `lifecycle:shipping`

It also reports inbox labels (`inbox:*`, `kind:rdr-seed`) and batch labels
(`batch:*`).

## Reaper

The read-only reaper surfaces inconsistent states. It never fixes them.

- orphaned claim: ship owner exists without a phase label
- abandoned mid-ship: phase label exists without an owner
- double lifecycle: more than one `lifecycle:*` label
- stale reviewed: `lifecycle:reviewed` has aged past the configured threshold
- stale RDR seed: `kind:rdr-seed` has aged past the configured threshold
- RDR-tracked drift: `kind:rdr-tracked` no longer matches the bound RDR status

## Mutation Rule

The ship orchestrator is the single writer for kata lock/label transitions.
Sub-agents may read kata state and report verdicts, but they must not mutate
ownership or lifecycle labels unless their parent skill explicitly delegates
that action.

