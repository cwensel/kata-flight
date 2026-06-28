# kata-flight — cold rationale

Extended reasoning for `skills/kata-flight/SKILL.md`. Read on demand (cited by
`§anchor`); never loaded into a hot run. Operative rules live in the SKILL.

## §why-no-sub-agent-full

`/kata-ship` is a **spawning** skill — it runs each resolve/refine/ship phase in
a spawned `Agent`, which is legal only from a context that can spawn. **A
sub-agent cannot spawn** (`Task is not available inside subagents`). So a
per-kata wrapper sub-agent would push kata-ship's phase spawns to L2, where they
refuse and the ship stalls. The orchestrator invoking `/kata-ship` directly (an
inline `Skill` call, which stays in the orchestrator's context) keeps it at L0,
where the phase spawns are legal L0→L1.

Isolation is **not** sacrificed by staying flat. kata-ship runs each leaf phase
in its own isolated agent that returns a verdict only (worktree-ship-pipeline
§leaf-agent-contract); the orchestrator keeps those verdicts and **surfaces a
one-line summary per leaf**, never the raw phase reports. What stays top-level is
the *orchestrator*, not the leaves — it must remain at L0 because it has to spawn
(a sub-agent can't), and the leaf agents spawn legally L0→L1 from there.

`/goal` and `/loop` are not used — they share the calling conversation's
context, which defeats the orchestration boundary (one verdict per kata, prep
ops parent-owned).
