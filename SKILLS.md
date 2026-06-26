# Kata Flight Skills

Short index, grouped by role. See [ARCHITECTURE.md](ARCHITECTURE.md) for how
they fit together (the skill-role table, the flight/review loop, and the
rdr-seed peel-off).

**Kinds:** *entry* = you invoke it · *orchestrator* = fans out to other skills ·
*leaf* = runs inside an orchestrator · *library* = read by reference (cited by
`§anchor`), never invoked.

## Setup & observe

- `kata-flight-init` *(entry)* — bind a consumer repository to this skill suite
  and, optionally, to an RDR engine checkout.
- `kata-flight-doctor` *(entry, read-only)* — verify the Kata Flight seam,
  engine, context root, optional RDR binding, and skill links.
- `kata-flow-ops` *(entry, read-only)* — dashboard and stuck-state queries over
  the kata lifecycle labels.
- `kata-inbox` *(entry / orchestrator)* — drain `inbox:hold` and
  `inbox:needs-review` through human-approved dispositions.

## Ship (kata-driven)

- `kata-flight` *(entry / orchestrator)* — select and ship a batch of katas;
  orders the wave, runs the review gate, then invokes `kata-ship` per kata.
- `kata-ship` *(orchestrator)* — resolve, refine with roborev, fast-forward
  merge, and close one or more kata issues. Wrapped by `kata-flight`.
- `kata-resolve` *(leaf)* — fix one or more kata issues in an isolated worktree.
  Invoked inside `kata-ship`.
- `kata-scope-review` *(entry / orchestrator)* — review, consolidate, and route
  kata batches before a flight. Run as `kata-flight`'s default review gate.
- `prompt-ship` *(entry / orchestrator)* — run a free-form prompt through the
  shared worktree shipping pipeline without creating kata issues.

## RDR track

- `roborev-triage` *(orchestrator)* — one-pass triage of roborev findings after
  an RDR-backed implementation launch; files `src:roborev` follow-up katas.
- `rdr-seed-triage` *(entry / orchestrator)* — drain the `kind:rdr-seed` kata
  backlog into RDR-ready shapes. Drains what `kata-scope-review` fills.
- `rdr-implement-triage` *(entry / orchestrator)* — build an RDR (Stage 8) and
  triage its roborev findings unattended.
- `rdr-implement-land` *(entry / orchestrator)* — land an RDR implementation
  branch and kick off the follow-up kata flight.

## Reference libraries (read, not invoked)

- `worktree-ship-pipeline` *(library)* — shared worktree/refine/merge protocol
  consumed by the ship skills via `§anchor` citation.
- `lib-land-rdr` *(library)* — shared RDR-landing tail consumed by the
  `rdr-implement-*` skills.
- `using-git-worktrees` *(library / playbook)* — generic worktree isolation
  helper.
