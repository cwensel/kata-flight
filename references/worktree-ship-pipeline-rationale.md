# worktree-ship-pipeline — cold rationale

Incident history and "why alternatives failed" detail for
`skills/worktree-ship-pipeline/SKILL.md`. Read on demand (cited by `§anchor`);
never loaded into a hot run. The operative rules live in the SKILL; this file
only carries the *why*.

## §worktree-creation-rationale-full

Why raw `git worktree add` and **no `EnterWorktree` in any form**:

`/kata-flight` and `/kata-ship` are not always launched at L0. When the
invocation is itself spawned into an isolated / cwd-pinned context, the
orchestrator IS a pinned agent from the harness's view, and its CWD is the repo
root. In that context **both** `EnterWorktree` forms are refused:

- `EnterWorktree(name:)` — refused: *creating* a worktree mutates the
  process-wide CWD, which the harness forbids from a pinned agent.
- `EnterWorktree(path:)` — refused: *"the current working directory is the
  repository root, not an isolated worktree — switching is only available to
  sessions whose working directory is inside a worktree."* A pinned agent may
  only `path:`-switch when it is **already inside a worktree**, not from the
  repo root.

So there is no `EnterWorktree` form that works from a pinned orchestrator at the
repo root — the most common ship launch. (Both forms *do* work from a true
top-level L0 session; that false positive is exactly what misled two earlier
"fixes" — each validated only from a top-level session and assumed it
generalized to the pinned orchestrator. It does not. Don't re-derive
`EnterWorktree` from the tool doc-string a third time.)

A Bash `git worktree add` does not touch the harness CWD gate at all, so it is
accepted from every context — L0, pinned, sub-agent orchestrator. Nothing
downstream needs harness registration: the sub-agents enter the worktree via
`cd`/`git -C` (they cannot call `EnterWorktree` either), the parent reads
everything via explicit `-C`, and teardown is raw `git worktree remove`.
Registration was pure ceremony with no consumer; removing it removes the only
failure point.
