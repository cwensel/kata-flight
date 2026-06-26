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
