---
name: worktree-ship-pipeline
description: 'Shared reference for worktree isolation, roborev refine, squash, and fast-forward merge used by ship skills. Not invoked directly; read when kata-ship, prompt-ship, or related skills cite it.'
---

# worktree-ship-pipeline

The shared bones of every ship-variant skill in this repo.

**Not invoked directly.** Consumer skills (`/kata-ship`,
`/prompt-ship`, …) declare a small set of *parameters* and *cite*
sections of this file by anchor. The parameters are:

| Parameter | Meaning |
|---|---|
| `EXPECTED_REPO_BASENAME` | Repo this consumer ships (e.g. `consumer-repo`); §repo-anchor asserts `REPO_ROOT` ends in it |
| `WORK_SOURCE` | Where the agent's task description comes from (kata body, user prompt, …) |
| `SHORT_ID` | Stable identity for the worktree + branch |
| `BRANCH` | `worktree-<SHORT_ID>` — the branch `git worktree add -b` creates in §phase-1b |
| `WORKTREE_PATH` | `.claude/worktrees/<...>` — must literally match the worktree directory |
| `TARGET_BRANCH` | Primary checkout branch captured at preflight; rebase/refine/ff-merge target |
| `INTENT_FIELD` | Name of the 1–3 sentence intent field in Phase-1 reports (`intent_excerpt`, `resolve_intent_excerpt`, …) |
| `FILES_MAX`, `DELETIONS_MAX` | Phase-1d scope-gate floor |
| `TIEBREAKER_4` | Consumer-specific out-of-scope-finding protocol (kata-ship: KATA_PUSH; prompt-ship: ask user) |
| `TIEBREAKER_5` | Optional multi-target auto-mode tiebreaker (kata-ship: yes; prompt-ship: n/a) |
| `LOCK_ANCHOR` | What "owning a session" means (kata.owner; branch + persisted prompt file; …) |
| `CLOSE_STEP` | Phase-3b post-merge work (kata close; echo-only; …) |

Section anchors below are part of the contract. Renaming any anchor
breaks every consumer; treat the anchor list as a public API.

---

## §repo-anchor

The isolation gate (§worktree-isolation-gate) proves a worktree is
linked to *whatever repo the parent is in* — never that it's the
**intended** repo. The anchor (`REPO_ROOT`) is captured from the
parent CWD at preflight, and §phase-1b pins every `git` to it via
`-C "$REPO_ROOT"` — but if the anchor itself drifted from a leaked
`cd`, those commands target the wrong repo. With sibling checkouts on
different
non-empty branches (e.g. `process` on `the configured RDR docs branch`), a leaked `cd`
lands in the wrong repo, `TARGET_BRANCH` is non-empty so preflight
passes, and the worktree is created there — every relative gate still
green. This section anchors all of that to an absolute, named repo.

**Capture once at preflight, before any other gate** (consumer names
its `EXPECTED_REPO_BASENAME`, e.g. `consumer-repo`):

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"           # absolute root, NOT pwd
[ -f "$REPO_ROOT/.kata-flight/env" ] && . "$REPO_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$REPO_ROOT")}"
[ "$(basename "$REPO_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$REPO_ROOT" >&2; exit 1; }
```

`REPO_ROOT` is the anchor for everything: `== PRIMARY_ROOT` in the
valid parent state, and every `git -C <MAIN_WT>` below means
`git -C "$REPO_ROOT"`. Pass it in every brief; never trust ambient
CWD for a repo-relative command again.

**Resolve `KATA_FLIGHT_CONTEXT_ROOT` (and the other workspace paths) from the
workspace marker** — the consolidated, *tracked* resources
optional `context/` and `rdr/evidence/` resources.
The Kata Flight marker is the single source of truth; source it here, where the topology is
anchored, so every consumer that cites §repo-anchor inherits the
exported paths:

```sh
PRIMARY_ROOT="$REPO_ROOT"
WS="$(dirname "$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd -P)")")"
KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
if   [ -f "$PRIMARY_ROOT/.kata-flight/workspace" ]; then . "$PRIMARY_ROOT/.kata-flight/workspace"; elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"; fi
[ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
```

`WS` keys off `git-common-dir` — the **main** repo's `.git` even from a
worktree — so it resolves correctly from any worktree and regardless of
this skill being installed from a plugin or symlinked into a consumer repository. (Do **not**
substitute `dirname "$PRIMARY_ROOT"`: from a worktree `PRIMARY_ROOT` is the
worktree root, whose parent is not the workspace.) Sourcing the marker also
exports the Kata Flight context paths. Pass `KATA_FLIGHT_CONTEXT_ROOT`
in every brief alongside `PRIMARY_ROOT`.

**Re-assert before each parent-side repo-mutating step** — worktree
creation (§phase-1b), ff-merge + teardown (§phase-3), resume
re-attach (§resume-mechanics):

```sh
[ "$(git rev-parse --show-toplevel)" = "$REPO_ROOT" ] || { echo "stopped:repo-anchor-drift" >&2; exit 1; }
```

This catches ambient CWD drifting off `$REPO_ROOT` between phases —
the leaked-`cd` failure. Every parent `git` uses explicit
`-C "$REPO_ROOT"`, so the drift check is belt-and-suspenders, but
keep it: a wrong anchor would still send the new worktree into the
wrong repo. Recover by surfacing, never a Bash `cd` (doesn't
propagate to the parent's tool CWD).

**Divergence advisory (non-fatal).** §local-main-truth forbids
fetch/pull/push; local is truth. But the silent `local ≠ origin`
gap is what masked the wrong-repo state in the incident — so surface
it once at preflight, without fetching (counts use the already-stored
remote ref; visibility, not accuracy):

```sh
UP="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref @{upstream} 2>/dev/null || true)"
if [ -n "$UP" ]; then
  set -- $(git -C "$REPO_ROOT" rev-list --left-right --count "$TARGET_BRANCH...$UP" 2>/dev/null)
  [ "$#" -eq 2 ] && [ "$1 $2" != "0 0" ] && echo "note: local $TARGET_BRANCH $1 ahead / $2 behind $UP (local is truth; no fetch)"
fi
```

The `$# -eq 2` guard matters: if `@{upstream}` resolves but the
`rev-list` fails (remote ref pruned locally), `set --` is empty and
an unguarded `"$1 $2" != "0 0"` would print a garbled note.

---

## §worktree-invariant

**Inline this section verbatim in every agent brief.**

The parent never edits files in the primary checkout, never commits,
never runs tests. The parent's only state-mutating operations are
worktree lifecycle: `git worktree add` in Phase 1b and
`git worktree remove` in Phase 3 teardown — **both raw Bash git, no
`EnterWorktree`/`ExitWorktree`**. All code work — read, edit, rebase,
lint, test, squash, ff-merge — happens inside an agent operating under
the worktree.

- **Phase-1 parent creates the worktree** before spawning the work
  agent — via a single Bash `git worktree add -C "$REPO_ROOT"`. **Do
  not use `EnterWorktree` in any form.** Neither `EnterWorktree(name:)`
  nor `EnterWorktree(path:)` works when the orchestrator is itself a
  cwd-pinned / subagent context sitting at the repo root — the exact
  context a `/kata-flight` spawned as a subagent runs in (`name:` is
  refused because creation mutates the process-wide CWD; `path:` is
  refused with "the current working directory is the repository root,
  not an isolated worktree"). Raw `git worktree add` never touches the
  harness CWD gate, so it is the only context-uniform mechanism —
  works at L0, from a pinned orchestrator, and from a sub-agent
  orchestrator alike. See §phase-1b-worktree-creation and
  §worktree-creation-rationale. The worktree persists for the
  sub-agents.
- **Phase-1, Phase-2, Phase-3 agents receive `worktree_path` and
  `branch` in their brief** and operate exclusively under the
  worktree. A sub-agent's cwd is **pinned at the repo root** and
  `EnterWorktree` is refused there (verified: "the current working
  directory is the repository root, not an isolated worktree"), so the
  durable way in is **`git -C <worktree_path>` on every git call**, or a
  self-contained `cd <worktree_path> && …` within a single Bash call.
  **A bare `cd` does NOT persist to the next Bash call** (each call
  re-starts at the pinned root) — never rely on a one-time `cd`. The
  §worktree-isolation-gate and every phase op below are written `git -C
  <worktree_path>` for exactly this reason.
- After every phase, parent verifies (one-line each):
  ```sh
  git worktree list --porcelain | grep -q "^branch refs/heads/<BRANCH>$"
  [ "$(git -C <MAIN_WT> branch --show-current)" = "$TARGET_BRANCH" ]
  [ -z "$(git -C <MAIN_WT> status --porcelain)" ]   # primary tree still clean
  ```
  Any check fails → abort intact for `--resume`. **The clean-primary
  check is the authoritative catch for a leaf that wrote into the primary
  checkout** (the §scope-discipline `$WORKTREE_PATH`-rooted-path rule
  prevents it; the `deny-primary-write` hook is best-effort and was
  observed not to fire on sub-agents — so this parent-side gate, not the
  hook, is what guarantees the leak is caught). Preflight requires the
  primary clean at start, so any dirt here is attributable to the just-run
  leaf: treat a non-empty `status --porcelain` as a worktree-invariant
  breach, surface the offending paths, and do not advance.
- If a report claims a `worktree_path` that resolves to the primary
  checkout (via `git rev-parse --git-common-dir` comparison), treat
  the phase as failed regardless of other contents.
- **Sibling worktrees are invisible.** Other ship sessions may have
  linked worktrees in this repo. They are not yours. Filter
  `git worktree list` to your own branch; never
  `ls .claude/worktrees/`. Do not read, classify, or report sibling
  state. Do not narrate ignoring it.

### §worktree-isolation-gate (the formula consumer skills cite)

A worktree is "isolated" iff both hold:

```sh
# same repo — normalize both common-dirs to absolute (see note below)
[ "$(git -C <WORKTREE_PATH> rev-parse --path-format=absolute --git-common-dir)" \
  = "$(git -C <MAIN_WT> rev-parse --path-format=absolute --git-common-dir)" ]
# linked, not primary — both reads from the SAME -C, so no normalization needed
[ "$(git -C <WORKTREE_PATH> rev-parse --git-dir)" != "$(git -C <WORKTREE_PATH> rev-parse --git-common-dir)" ]
```

Either condition false → the agent worked in the primary despite
reporting a worktree_path; treat the phase as failed.

> **The same-repo compare MUST normalize.** `--git-common-dir`
> returns a path **relative to the queried dir**: from a linked
> worktree it's absolute (`/…/<repo>/.git`), from the primary
> checkout it's the bare relative `.git`. A naked string compare of
> the two therefore *always* fails (verified). `--path-format=absolute`
> (git ≥ 2.31) forces both to absolute; if unavailable, wrap each in
> `(cd "$(git -C <dir> rev-parse --git-common-dir)" && pwd -P)`. The
> second clause is immune — both its reads come from one `-C
> <WORKTREE_PATH>`, so they share the same relative/absolute base.

---

## §scope-discipline

**Inline this section verbatim in every work-agent brief** (Phase-1
resolve/execute, and any Phase-2/Phase-3 agent that edits files). It
is the *proactive* contract behind the §phase-1d-verify-shared
detector — the gate catches overreach after the fact; this prevents
it up front.

Two standing rules, both about staying inside the unit of work:

1. **Commit only in-scope paths.** The unit of work is the
   task-source's named target (the kata's fix + its new test, the
   prompt's named files) plus the direct callers/tests that the named
   edit *forces*. NEVER edit, clean up, refactor, or **weaken** any
   unrelated test or source. In particular: do not relax an assertion
   (`t.Fatalf` → permissive `if`, exact-match → substring scan), do
   not delete a helper, do not loosen a guard to make something green.
   - A broad `go test ./...` that surfaces a **pre-existing,
     unrelated** failure is NOT yours to fix. Scope your verification
     run to the package(s) you touched (`go test ./internal/cli/...`
     or a `-run` filter); if a broad run is informative, **report** the
     unrelated failure in your intent field — do not chase it into an
     edit.
   - If an unrelated file genuinely must change for your fix to be
     correct (a forced caller, a shared signature), that is a scope
     question, not a license: **STOP and return a tiebreaker** (a
     scope-expansion stop — wanting to *edit* out-of-scope code, distinct
     from tiebreaker-4 which dispositions a *finding* about it) rather
     than editing it silently.
   - Before committing, list your changed paths and confirm each maps
     to the unit of work. Report the final set as `in_scope_paths` so
     the parent gate can verify nothing slipped in under the count
     floor.

2. **Writes are worktree-only; every tool path is `$WORKTREE_PATH`-rooted.**
   Every file-mutating operation targets the worktree, never the primary
   checkout. Reads from `$KATA_FLIGHT_CONTEXT_ROOT` (`rdr/evidence/`, `context/`) are
   fine and expected; **writes there are never correct.**

   **The `Edit`/`Write`/`Read` tools resolve their `file_path` against
   the *parent* cwd, NOT your Bash cwd** — a Bash `cd` into the worktree
   does **not** move them (spike finding, kata qrsf). So a `file_path`
   like `internal/cli/foo.go` (relative) or
   `<REPO_ROOT>/internal/cli/foo.go` (repo-rooted, no `worktrees/<id>`
   segment) silently resolves into the **primary checkout** — this is the
   exact leak that read as "picked up work from another session"
   (flow#<this-investigation>). Hard rules:

   - **Build every `Edit`/`Write`/`Read` `file_path` as
     `$WORKTREE_PATH/<relative>`** — absolute, worktree-rooted. Never a
     bare relative path; never a `$REPO_ROOT/…` path that omits the
     `.claude/worktrees/<SHORT_ID>/` segment.
   - **Self-check before your FIRST edit** (and whenever you assemble a
     path by hand):
     ```sh
     case "$FP" in
       "$WORKTREE_PATH"/*) : ;;                      # ok — inside the worktree
       *) echo "stopped:primary-path-leak:$FP" >&2; exit 1 ;;  # abort, do not edit
     esac
     ```
   - For Bash, operate via `cd "$WORKTREE_PATH"` (each Bash call is a
     fresh shell — re-`cd` or compound `cd … && …` every call) or
     `git -C "$WORKTREE_PATH"`. `pwd -P` when in doubt about where a path
     lands.

   An ad-hoc path clause has leaked more than once — treat this as a hard
   gate, not a reminder.

   > **Harness backstop — verify, don't assume.** A `PreToolUse` hook
   > (`.claude/hooks/deny-primary-write.py`, kata qrsf) is *meant* to
   > hard-deny any sub-agent `Edit`/`Write` whose absolute path is inside
   > the repo but outside `.claude/worktrees/`. **But it did not fire on
   > the sub-agent leak that motivated this clause** — the hook lived only
   > in `.claude/settings.local.json`, which the sub-agent's settings
   > scope did not load (it was also duplicated into `.claude/settings.json`
   > as the candidate fix; whether *that* source reaches sub-agents needs a
   > fresh-session check — Claude Code's docs say PreToolUse fires on
   > sub-agents via `agent_id`, but the settings-source inheritance for
   > sidechains is under-documented). **Treat the hook as best-effort
   > defense in depth, NOT a guarantee.** The `$WORKTREE_PATH`-rooted-path
   > rule + self-check above is the primary discipline; the parent's
   > post-phase primary-tree gate (§worktree-invariant) is the
   > authoritative catch.

---

## §local-main-truth

All baselines are the local primary checkout branch captured at
preflight as `TARGET_BRANCH` (memory `local-main-is-truth` still
applies: local branch state is authoritative). Remote refs may lag;
no `git fetch` / `pull` / `push` anywhere in this pipeline.

§phase-1b bases the worktree branch explicitly off local
`TARGET_BRANCH` (`git worktree add … "$TARGET_BRANCH"`), so this rule
holds regardless of the `worktree.baseRef` setting.

---

## §context-discipline

See §leaf-agent-contract — the leaf/orchestrator split *is* the context
discipline. (Anchor kept for back-references; the contract below subsumes it.)

## §leaf-agent-contract

The pipeline has exactly two kinds of skill, partitioned by one hard
constraint: **a harness agent cannot itself spawn** (`Task is not available
inside subagents`). So:

- **Orchestrators fan out → run TOP-LEVEL, never as an agent.** `kata-flight`
  (per-kata loop) and `kata-ship` (spawns its phases) invoke leaves via the
  Agent tool (L0→L1), and a flight invokes `/kata-ship` via an inline top-level
  `Skill` call (kata-flight §Why-no-per-kata-sub-agent). Wrapping an
  orchestrator in a sub-agent pushes its spawns to L2, where they refuse — the
  spawn wall.
- **Leaves do one bounded job → run AS an agent, return a verdict.** Each ship
  phase (resolve / rebase+refine / ship), standalone `kata-resolve`, and the
  per-item grounding in `roborev-triage` / `kata-scope-review` are leaves. A
  leaf spawns nothing and returns a **structured verdict**, never its raw
  transcript.

The leaf-agent rules (this is the contract consumers cite):

1. **Parent owns coordination.** Leaves only read coordination state, never
   mutate it. Parent owns lock state, tiebreakers, and the kata close.
2. **Each leaf gets a self-contained brief** with `$SESSION_ID`,
   `worktree_path`, `branch`, `TARGET_BRANCH`, the worktree invariant verbatim,
   §scope-discipline verbatim (for any file-editing leaf), tiebreaker rules
   verbatim, report schema + budget, and the consumer's work-source content.
3. **Verdict-only return — no raw transcript.** The leaf returns ONLY its
   structured report; the parent keeps the verdict and **surfaces a one-line
   summary**, never the raw output. This is the isolation win — heavy
   resolve/refine/grounding token volume stays in the leaf, off the
   orchestrator's context. Default budgets: Phase-1 ≤150–200 words, Phase-2
   ≤200, Phase-3 ≤250 (squash sub-report ≤200 folded in). SHAs + file:line
   fine; pasted source / diffs / test output **forbidden**. *Visibility is the
   verdict, not the transcript* — widen a report schema if a real gap surfaces;
   never revert to raw inline output.
4. **Independent leaves may run concurrently.** Nothing in the contract
   serializes leaves; only the ff-merge is a true barrier (parallel ship, kata
   nnv8). A leaf is a pure brief→verdict function.
5. **Tiebreakers return-and-respawn** (§tiebreakers-shared Mechanic): the leaf
   returns the packet, parent asks, parent respawns a fresh continuation leaf
   with the disposition baked in. Live `SendMessage` to the same agent id is an
   optional fast-path where the harness has it.
6. **Skills run inside leaves** — `/roborev-refine`, `/roborev-respond`, and
   consumer-specific resolve skills are invoked by the leaf via `Skill`, never
   by the parent.

Decision record (author's RDR engine, not shipped):
`flow/rdr/RDR-LEAF-PHASE-AGENTS.md`.

---

## §preflight-shared

Hard stops; refuse, do not ask. Consumer skills may add gates
above and beyond these.

0. **§repo-anchor capture** — set + verify `REPO_ROOT` (expected
   basename) before any other gate, so a leaked `cd` into a sibling
   repo can't pass the gates below. All gates 1–3 use
   `git -C "$REPO_ROOT"`.
1. `git -C "$REPO_ROOT" status --porcelain` empty.
2. Capture `TARGET_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"`;
   non-empty. Then emit the §repo-anchor divergence advisory.
3. `roborev status` exits 0 (catches unhealthy queue or
   uninitialized repo before any side-effects). Do not front-load
   daemon checks: use normal kata/roborev commands. Run `kata daemon
   status/start` only after a normal kata command fails; do not run
   `roborev daemon ...` proactively.

---

## §coordination-shared

```sh
REPO_ROOT="$(git rev-parse --show-toplevel)"   # §repo-anchor; assert expected basename
SHORT_ID="<consumer-defined>"           # kata short-id, prompt uuid, …
SESSION_ID="<skill-name>/<short-id-or-uuid>"
BRANCH="worktree-<SHORT_ID>"            # or worktree-prompt-<SHORT_ID>, etc.
WORKTREE_PATH="$REPO_ROOT/.claude/worktrees/<SHORT_ID>"   # absolute, anchored
TARGET_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
```

`WORKTREE_PATH` is absolute (`$REPO_ROOT/...`) so it can't reattach to
a drifted CWD. `<MAIN_WT>` in every gate below = `"$REPO_ROOT"`.

The branch name + worktree directory pair is the *physical* lock.
Consumer skills may add a logical lock (kata owner, persisted file)
on top.

**Never strip another session's lock.** Sibling worktrees and
sibling locks are out of scope (see §worktree-invariant).

---

## §tiebreakers-shared

**Universal tiebreakers (every consumer inherits these):**

1. HIGH finding that looks like a false positive.
2. Finding contradicts the agent's work-source content (work
   prompt, kata body, …) or cited reference.
3. Rebase conflict that `rerere` cannot clear.

**Roborev-finding tiebreakers auto-dispose by default (1, 2, 4).** These
are *evidence* decisions — the agent holds the RDR, critiques
(`$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`), work source, and source — the same
grounding `roborev-triage` runs unattended on. So 1/2/4 are decided from
that evidence and applied without asking (see §Mechanic), recording the
verdict + grounding so the close is auditable. **3 and 5 still stop**: a
`rerere`-unclearable conflict (3) has no safe default and multi-target
auto-mode (5) is a coordination stop. (A consumer may re-gate 1/2/4.)

**A stale/orphaned review job is finding-disposition, not a lock-stop.** An
orphaned review — no live owner, its commit reworded/superseded so its
tree+parent are identical to the current base, and its findings verifiably
already fixed in HEAD — is *evidence-decidable debris*, so it auto-disposes
in-flight (close it, citing the grounding) like a tiebreaker-1/2. Do **not**
surface it as a stop. The "never strip another session's *lock*" rule
(`kata-ship` §) protects a **live owner/claim**; an orphaned review object
carries no claim, so closing it strips nothing. "Belongs to another session"
is not, by itself, an authorization gate — only a live lock is. (The roborev
`close` allowlist already grants the capability; the only question is the
evidence, and orphan + identical-tree + fixed-in-HEAD settles it.)

**Consumer-defined slots:**

- Tiebreaker 4: out-of-scope finding. Consumer declares the
  protocol (`TIEBREAKER_4`). Examples: kata-ship's `KATA_PUSH:`
  packet; prompt-ship's `fix-now / defer / false-positive`
  question. When the disposition spins the finding off to a
  tracker (kata, issue), the packet must clear §spinoff-worthiness
  first.
- Tiebreaker 5 (optional): multi-target auto-mode. Consumer
  declares whether this applies (`TIEBREAKER_5`). When a *stop*
  tiebreaker (3, or 1/2/4 under a re-gating consumer) fires during a
  serial batch, pause that item, ask, continue; auto-disposed
  findings never pause.

**Not prompts:** pre-flight failures, `--resume`, refine flapping,
phase transitions — all deterministic.

### §spinoff-worthiness

When a tiebreaker disposition would **spin a finding off to a
tracker** (a new or attached kata/issue) rather than fix it now or
drop it, the deciding agent first **ultrathinks the spin-off
itself** — the decision to defer is a judgement, not a reflex, and a
thin or speculative kata is debt, not progress. Before emitting the
packet:

1. **Worth deferring?** Confirm it is a real, reachable defect that
   genuinely doesn't belong in this unit of work — not a false
   positive, not already adjudicated by the RDR/critiques (read them
   via `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`), not scoped out by a standing
   project decision, not over-engineering against a hypothetical
   (`docs/principles.md`). If any of those hold, the disposition is
   DROP/respond, not spin-off. Dropping needs positive evidence;
   so does deferring.
2. **Attach before create.** Search existing open trackers first
   (`kata search` + `kata list`); a fitting home beats a duplicate.
3. **Well-reasoned, self-contained body.** A reader who never saw
   this branch must be able to act on it. Include: **Problem** (what
   + where, `file:line`), **Threat model / reachability** (the live
   path, or why it can't currently fire), **Grounding** (the RDR
   section / corpus / invariant evidence consulted in step 1),
   **Course of action** (the fix shape, not a full patch), and an
   **`## Open question`** section when the evidence left a tension —
   stating it + the agent's recommendation so the shipping run
   resolves it rather than re-deriving it.

The packet the agent returns to the parent stays terse (≤80 words —
the parent files the body); but the **body it proposes** carries the
above. Consumers cite this section from their `TIEBREAKER_4`.

### Mechanic

**Auto-dispose path (1, 2, 4 — default).** The agent clears
§spinoff-worthiness, decides from the evidence in hand, and **applies it
in-flight — no return to parent, no ask**:

- **1 (HIGH FP)** confirmed FP → `/roborev-respond` dismiss citing the
  refuting grounding; continue.
- **2 (contradicts source)** → respond/dismiss when the source decision
  governs (cite it); else treat as real and fix or push per scope.
- **4 (out-of-scope)** → per the consumer's `TIEBREAKER_4` (kata-ship
  files/attaches the kata and `/roborev-respond`s the job).
- **Orphaned/stale review** (no live owner, identical tree+parent to base,
  findings already in HEAD) → `roborev close <job>` citing the orphan grounding
  (the superseding ref + the HEAD fixups that resolve each finding); continue.
  Never surface this as a stop.

Record the verdict + grounding in the terminal report so the close is
auditable. Evidence can't settle it → `roborev-triage` defaults
(drop-vs-file → file; severity → higher); never ask.

**Stop-and-ask path (3, 5 only).** Default — **return-and-respawn** (no
live messaging required; works in any harness):

1. Agent emits a `TIEBREAKER:` packet (condition #, ≤80-word context,
   proposed disposition) as its **terminal report** and returns. Its
   report carries `head_sha` + worktree state so the handoff is
   verifiable; the worktree/branch persist untouched.
2. Parent surfaces via `AskUserQuestion` (or direct text question).
3. Parent re-verifies worktree state, then **respawns a fresh
   continuation agent** for the same phase with the disposition baked
   into its brief (same `$SESSION_ID`, `worktree_path`, branch). The
   agent re-runs the §worktree-isolation gate, applies the disposition,
   and continues.

Fast-path — where the harness exposes live agent messaging
(`SendMessage` to the same agent id): the agent may instead WAIT after
step 1 and the parent message the answer back, skipping the respawn.
Optional optimization only; the default above is authoritative.

**Ultrathink before applying** HIGH / cross-subsystem / structural /
`project_core_principles`-touching / intent-conflicting fixes.

**No unrecorded dismissals at any severity** — every dismissal carries
its grounding (auto-disposed via §Mechanic, or surfaced for 3/5).

---

## §phase-1b-worktree-creation

Parent owns worktree creation via **raw Bash `git worktree add` only**.
There is **no `EnterWorktree`/`ExitWorktree` step** — see
§worktree-creation-rationale for why every `EnterWorktree` form was
removed. A Bash `git worktree add` never touches the harness's CWD
gate, so creation is uniform across L0, a pinned orchestrator, and a
sub-agent orchestrator.

`WORKTREE_PATH` = `<REPO_ROOT>/.claude/worktrees/<SHORT_ID>`,
`BRANCH` = `worktree-<SHORT_ID>`.

0. **§repo-anchor re-assert.** Drift check
   (`git rev-parse --show-toplevel == REPO_ROOT`) before step 1;
   `stopped:repo-anchor-drift` on failure. (All `git` below uses
   explicit `-C "$REPO_ROOT"`, but the anchor must be right so the
   worktree lands in the correct repo.)
1. **Create via Bash** (does not mutate tool-call CWD; works from any
   launch context):
   ```sh
   git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE_PATH" "$TARGET_BRANCH"
   ```
   Bases off local `TARGET_BRANCH` HEAD explicitly (§local-main-truth;
   no longer needs `worktree.baseRef: head`). Existing path/branch → it
   fails loudly → `stopped:worktree-prep-failed`; never reuse silently.
2. Verify (parent, read-only, after step 1 returned). The parent's CWD
   is never moved (no `EnterWorktree`), so it stays in the primary
   checkout throughout; all checks use explicit `-C`:
   ```sh
   git -C "$REPO_ROOT" worktree list --porcelain | grep -q "^branch refs/heads/$BRANCH$"
   git -C "$REPO_ROOT" rev-parse --git-dir | grep -qx .git                # anchor still primary, not worktree
   [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]                     # primary clean (§worktree-invariant)
   [ "$(git -C "$WORKTREE_PATH" rev-parse HEAD)" = "$(git -C "$REPO_ROOT" rev-parse "$TARGET_BRANCH")" ]
   ```
   Any failure → `git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH"`
   if present, release any consumer lock, surface. **Not a `--resume`
   candidate** (no work done yet).
3. Record `worktree_path = WORKTREE_PATH`, `branch = BRANCH` for the brief.

### §worktree-creation-rationale

Why raw `git worktree add` and **no `EnterWorktree` in any form**:

`/kata-flight` and `/kata-ship` are not always launched at L0. When the
invocation is itself spawned into an isolated / cwd-pinned context, the
orchestrator IS a pinned agent from the harness's view, and its CWD is
the repo root. In that context **both** `EnterWorktree` forms are
refused:

- `EnterWorktree(name:)` — refused: *creating* a worktree mutates the
  process-wide CWD, which the harness forbids from a pinned agent.
- `EnterWorktree(path:)` — refused: *"the current working directory is
  the repository root, not an isolated worktree — switching is only
  available to sessions whose working directory is inside a worktree."*
  A pinned agent may only `path:`-switch when it is **already inside a
  worktree**, not from the repo root.

So there is no `EnterWorktree` form that works from a pinned
orchestrator at the repo root — the most common ship launch. (Both
forms *do* work from a true top-level L0 session; that false positive
is exactly what misled two earlier "fixes" — each validated only from
a top-level session and assumed it generalized to the pinned
orchestrator. It does not. Don't re-derive `EnterWorktree` from the
tool doc-string a third time.)

A Bash `git worktree add` does not touch the harness CWD gate at all,
so it is accepted from every context — L0, pinned, sub-agent
orchestrator. Nothing downstream needs harness registration: the
sub-agents enter the worktree via `cd`/`git -C` (they cannot call
`EnterWorktree` either), the parent reads everything via explicit
`-C`, and teardown is raw `git worktree remove`. Registration was pure
ceremony with no consumer; removing it removes the only failure point.

Consumer skills may insert additional steps (e.g. persisting a
work-source file inside the worktree) between step 4 and the
agent spawn. Per-worktree files written here must rely on the repo
root `.gitignore` already excluding `.claude/` — **do not touch
`.git/info/exclude`**: in a linked worktree, `.git` is a *file*
pointing into the shared git common dir, so `info/exclude` is
shared across all worktrees + the primary; editing it pollutes
everything.

---

## §phase-1d-verify-shared

After the work agent returns, parent verifies (one line each):

```sh
# Worktree-isolation gate (see §worktree-isolation-gate)
[ "$(git -C <WORKTREE_PATH> rev-parse --path-format=absolute --git-common-dir)" = "$(git -C <MAIN_WT> rev-parse --path-format=absolute --git-common-dir)" ]   # normalized; see §worktree-isolation-gate
[ "$(git -C <WORKTREE_PATH> rev-parse --git-dir)" != "$(git -C <WORKTREE_PATH> rev-parse --git-common-dir)" ]
git -C <MAIN_WT> branch --show-current              # == $TARGET_BRANCH
git -C <WORKTREE_PATH> branch --show-current        # == <BRANCH>
git -C <WORKTREE_PATH> rev-parse --short HEAD       # == reported head_sha
git -C <WORKTREE_PATH> rev-list --count "$TARGET_BRANCH"..HEAD  # >= 1
git -C <WORKTREE_PATH> diff --shortstat "$TARGET_BRANCH"..HEAD  # files <= <FILES_MAX> AND deletions <= <DELETIONS_MAX>
git -C <WORKTREE_PATH> log -1 --format=%B           # body non-empty when shortstat trips
git -C <WORKTREE_PATH> diff --name-only "$TARGET_BRANCH"..HEAD  # every path ∈ reported in_scope_paths
```

Any failure → stop intact for `--resume`. Scope gate is a
parent-side floor against runaway agents; the consumer's work-source
skill (when applicable) owns the primary gate.

**In-scope-set check (§scope-discipline backstop).** The `FILES_MAX`/
`DELETIONS_MAX` floor only catches *runaway* overreach; a *small*
unrelated edit (e.g. one weakened test file) sits under the floor.
So additionally diff `--name-only` and confirm every committed path
is a member of the agent's reported `in_scope_paths`. Any path NOT
in that set → treat as a scope-gate trip (surface the offending
path(s) to the user; user answers `proceed` or `abort` per
§failure-recovery-shared). This is the structural complement to the
§scope-discipline prompt clause: the prompt asks the agent to stay
in scope; this catches it if it didn't. A work agent that omits
`in_scope_paths` is treated as reporting the empty set (every path
is out-of-scope) → trip.

**Exception:** consumer skills may declare specific stop-verdicts
(e.g. `stopped:worktree-isolation-failed`, `stopped:needs-triage`,
`stopped:empty-result`) where the worktree is empty by contract and
the appropriate recovery is teardown rather than `--resume`.

---

## §phase-2-rebase-refine

**Order: rebase first, then refine.** One rebase per ship; refine
reviews the branch's commits against current trunk = what will ship.
Single agent owns both steps — parent stays out of the worktree.

### Label / lock transition (consumer-defined)

Consumer skill performs any lock/label transition here. The shared
mechanic from this point onward is the same across consumers.

### Spawn rebase+refine agent

`Agent(subagent_type: "general-purpose")`. Brief (capture the agent id
only if using the §Mechanic fast-path):

- `$SESSION_ID`, `worktree_path`, `branch`, `TARGET_BRANCH`.
- **§worktree-invariant verbatim.**
- Consumer's `INTENT_FIELD` excerpt + cited references from Phase 1.
  Plus the verbatim work-source content (work prompt / kata body /
  …) so tiebreaker-2 has the authoritative intent.
- **`PRIMARY_ROOT` + `KATA_FLIGHT_CONTEXT_ROOT`** (absolute) so the agent grounds
  findings against the evidence roborev never saw — the governing
  RDR + critiques + conventions live in the configured Kata Flight context root:
  critiques at `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/critique/`, the broader RDR
  evidence under `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`, conventions at
  `$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md`. These are *tracked*
  in the configured context root, and `KATA_FLIGHT_CONTEXT_ROOT`
  is the primary checkout's sibling (§repo-anchor) — symlink-safe.
  Ground against the configured RDR evidence root, **not** the
  external RDR methodology repo. A finding the RDR already
  adjudicated, scoped out, or that contradicts a cited principle is
  a tiebreaker-2 (intent conflict) or a DROP, not a blind fix.
  Consumers pass both values; the few that legitimately have no
  governing RDR (a free-form prompt unrelated to any spec) still read
  `$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md` for conventions.
- §tiebreakers-shared verbatim, plus the consumer's
  `TIEBREAKER_4` and (optionally) `TIEBREAKER_5` specializations.
  Tiebreaker 1–2 → §Mechanic (auto-dispose by default; a consumer
  may re-gate). Confirmed FP → agent runs `/roborev-respond` + dismiss
  + re-enter loop, citing grounding. Real → continue.
- **Step 1: rebase.** `git -c rerere.enabled=true rebase "$TARGET_BRANCH"`.
  Conflict `rerere` can't clear → tiebreaker 3 per §Mechanic.
- **Step 2: refine.**
  `/roborev-refine --since "$TARGET_BRANCH" --max-iterations 5`.
  Branch is rebased onto current `TARGET_BRANCH`, so
  `TARGET_BRANCH..HEAD` = the branch's commits. Peer ff-merges
  advance `TARGET_BRANCH` during refine; `TARGET_BRANCH..HEAD`
  asymmetric-set-difference still scopes to this branch's commits.
- **Scope alarm**: a finding against files OTHER than this branch's
  commits is out-of-scope → tiebreaker 4 per §Mechanic (auto-disposed
  by default; consumer may re-gate).

### Report schema (≤200 words; consumer may add fields)

- `verdict`: `passed` | `flapping` | `daemon_unhealthy` | `stopped:<reason>`
- `rebase_outcome`: `clean` | `rerere-resolved` | `conflict`
- `iterations_run`, `tip_sha` (short)
- `commits_added`: `<short-sha> <subject>` lines (no bodies) —
  Phase 3 squash needs this
- `dismissed_findings`: `<severity> <file:line> — <reason>` (every
  dismissal cites its grounding; tiebreaker-4 dismissals cite the
  consumer-defined disposition reason; a re-gating consumer's
  user-approved dismissals cite that approval)
- `remaining_findings`: only on `flapping` / `stopped`
- `lint_clean`: bool

### Gate + worktree re-verify

```sh
git worktree list --porcelain | grep -q "^branch refs/heads/<BRANCH>$"
[ "$(git -C <MAIN_WT> branch --show-current)" = "$TARGET_BRANCH" ]
# §worktree-isolation-gate
[ "$(git -C <WORKTREE_PATH> rev-parse --path-format=absolute --git-common-dir)" = "$(git -C <MAIN_WT> rev-parse --path-format=absolute --git-common-dir)" ]   # normalized; see §worktree-isolation-gate
[ "$(git -C <WORKTREE_PATH> rev-parse --git-dir)" != "$(git -C <WORKTREE_PATH> rev-parse --git-common-dir)" ]
```

`verdict==passed` AND both checks pass → advance. Otherwise → stop
intact for `--resume`. `daemon_unhealthy` → surface the failing
normal roborev command/status output; do not start roborev manually.

---

## §phase-2-broadening

New refine run after `flapping`, not an extension. Parent:

1. **Close in-flight branch jobs**: `roborev fix --open --list` →
   `roborev respond` with broadening note → `roborev close <id>`.
2. **Re-spawn Phase-2 agent** with `rebase_already_done: true`
   (skip step 1) + fresh budget + prior `remaining_findings` for
   context. Optionally higher `--max-iterations` or different
   `--reasoning`.

---

## §phase-3-ship-agent

Single agent owns the entire phase. Parent only does any consumer
lock/label transition and the final `CLOSE_STEP`.

### Spawn ship agent

`Agent(subagent_type: "general-purpose")`. Brief:

- `$SESSION_ID`, `worktree_path`, `branch`, primary `MAIN_WT`,
  `TARGET_BRANCH`.
- **§worktree-invariant verbatim.**
- `commits_added` list from Phase 2.
- §tiebreakers-shared verbatim (tiebreaker 4 won't normally fire
  in ship; pass through for vocabulary consistency).

**Agent runs, in order:**

1. **Pre-merge checks.**
   ```sh
   roborev fix --open --list      # empty for branch
   git -C <WORKTREE_PATH> status --porcelain   # empty
   # §worktree-isolation-gate holds
   git -C <WORKTREE_PATH> branch --show-current  # == <BRANCH>
   ```
   Failure → stop.
2. **Re-rebase if `TARGET_BRANCH` moved.**
   ```sh
   if [ "$(git -C <WORKTREE_PATH> merge-base HEAD "$TARGET_BRANCH")" != "$(git -C <MAIN_WT> rev-parse "$TARGET_BRANCH")" ]; then
     git -C <WORKTREE_PATH> -c rerere.enabled=true -c core.hooksPath=/dev/null rebase "$TARGET_BRANCH"
   fi
   ```
   Conflict → tiebreaker 3, WAIT. `core.hooksPath=/dev/null`
   suppresses the `.githooks/post-commit` roborev enqueue per
   replayed commit — step 3 below (`go test && golangci-lint`,
   no refine) covers correctness on the rebased tip; per-commit
   reviews would be pure noise.
3. **Test + lint on rebased tip.**
   `go test ./... && golangci-lint run ./...`. Failure → real
   peer-interaction regression. Stop intact; report
   `verdict: stopped:test_lint_fail` with one-line failure
   summary. **No auto-refine** — refine's loop would just produce
   more peer-interaction commits.
4. **Squash (only if >1 fixup).** Apply §squash-rules. Post-checks:
   `git diff $PRE_SQUASH..HEAD` empty, tests pass, lint clean.
   Failure → reset to `$PRE_SQUASH`, set `squash_fell_back: true`,
   continue with un-squashed range.
5. **ff-merge.**
   ```sh
   git -C <MAIN_WT> merge --ff-only <BRANCH>
   ```
   Rejected → re-rebase, retry once; second rejection → stop intact.
6. **Tear down.** ExitWorktree is unavailable to sub-agents; use
   raw git:
   ```sh
   git -C <MAIN_WT> worktree remove <WORKTREE_PATH>
   git -C <MAIN_WT> branch -d <BRANCH>
   ```
   Both safe after ff-merge: branch is reachable from `TARGET_BRANCH`,
   worktree has no uncommitted state (step 1's status check).

### Report schema (≤250 words; squash sub-report ≤200 folded in)

- `verdict`: `shipped` | `stopped:<reason>`
- `merged_sha` (short), `summary`: one-line outcome
- `rebase_outcome_3_2`: `unchanged` | `clean` | `rerere-resolved` | `conflict`
- `tests_pass`, `lint_clean`: bool
- `squash`: `n/a` | `squashed` | `fell_back`; if squashed,
  `rollups`: `<short-sha> <subject>` per roll-up
- `teardown`: `clean` | `partial:<reason>`

---

## §squash-rules

Referenced from §phase-3-ship-agent step 4.

**Pairing.** Each fixup pairs with the original-intent commit that
spawned the chain. Fixup-of-fixup pairs with the original — read
body for cite (`review of <sha>`, kata slug, RDR ref). Adjacency
is a hint, not the rule.

**Grouping** (per original-intent commit):

- Pure `(High)`, pure `(Medium)`, `(High+Medium)` → standalone,
  one each.
- `(Medium+Low)` + `(High+Low)` → one roll-up.
- `(Low)` → one roll-up (distinct from M+L).
- Singleton in a bucket → leave alone; roll up at ≥2.

**Subject:** `<type>(<subsystem>): <outcome> follow-ups — <severity> (N findings)`

- `<type>`: `fix` default; `docs`/`test` if rollup is purely that.
- `<subsystem>`: from the original-intent commit's prefix (no
  synth unions).
- `<outcome>`: 4–8 words from the original-intent subject or cited
  reference.
- `<severity>`: literal `Low` / `Medium+Low` / `High+Low`.

**Forbidden in subject:** `roborev`, `job NNN`, kata slugs, roborev
IDs (memories `commit_subject_self_check`,
`no_kata_ids_in_commits`, `no_roborev_ids_in_commits`). Body cites
are fine.

**Body:** each original as `- <short-sha> <original subject>` under
`Squashed-from:` trailer. Originals keep tags verbatim.

**Placement:** roll-up takes slot of first fixup in group;
standalones keep slots. Don't pull a fixup back across an anchor
touching the same files — check
`git log --oneline <range> -- <path>`.

**Method:** `cleanup/low-squash` branch from pre-squash boundary.
`git cherry-pick -n` for contiguous groups then commit with
roll-up message; standalones use plain cherry-pick. Intermixed
standalones → cherry-pick individually then
`git reset --soft <base> && git commit -F <msg>`. Never `-i`.

**Suppress post-commit roborev during squash.** Prepend
`-c core.hooksPath=/dev/null` to **every** git invocation in this
step that creates a commit: `cherry-pick` (with or without `-n`),
`commit`, `commit -F <msg>`. Applies to standalones, contiguous
roll-ups, and the soft-reset path. Don't change repo config or
`.roborev.toml` — per-command, leaves no state to restore. The
post-squash `git diff $PRE_SQUASH..HEAD` empty check + tests + lint
already cover squash correctness.

**Conflicts** (expected when reordering across same-file anchors):

- `--theirs` default for comment-block divergences (later wins).
- After resolve, verify unique identifiers appear once
  (`grep -n '<token>'`) — relocation hunks can leave dead copies.
- Bad resolution → hard-reset, redo; clear `.git/rr-cache` first.

---

## §resume-mechanics

Consumer skills implement `--resume <identifier>`. The shared
mechanic:

1. **Ownership check** (consumer-defined `LOCK_ANCHOR`). The
   `--resume` target must already belong to a session of this
   consumer skill. Cross-consumer adoption is refused.
2. **Locate worktree.** Re-establish + re-assert `REPO_ROOT`
   (§repo-anchor) first — resume starts a fresh session, so the
   anchor must be re-captured. `git -C "$REPO_ROOT" worktree list
   --porcelain` for the expected branch. Worktree gone but branch
   exists → re-attach via raw git (parent, state-mutating but
   worktree-only):
   ```sh
   git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" <BRANCH>
   ```
   Both gone → refuse.
3. **Read any consumer-persisted intent** (work-source file, kata
   body cache, …). Missing required intent → refuse with a
   skill-specific `stopped:resume-*-missing` code.
4. **Mint fresh `$SESSION_ID`** (consumer-defined format). The
   `SHORT_ID` of the branch stays as identity; `$SESSION_ID` is
   per-invocation.
5. **Determine phase** by tip state:
   - 0 commits ahead of `TARGET_BRANCH` → Phase 1.
   - Commits present, refine not yet recorded as passed →
     Phase 2 (refine is idempotent and cheap when the tree
     already passes).
   - Refine recorded passed, ff-merge / teardown failed →
     Phase 3.
   When uncertain, re-run Phase 2.
6. **Re-run §phase-1d-verify-shared against the existing tip
   before resuming Phase 2.** A runaway commit from the prior
   session does not get amnestied by resume.

---

## §failure-recovery-shared

Most failures leave branch + worktree intact for `--resume`. The
"empty worktree by contract" rows are exceptions — parent removes
the empty worktree + branch because there is nothing to resume.

| Failure | Action |
|---|---|
| §repo-anchor `stopped:wrong-repo` / `repo-anchor-drift` | Refuse + surface `$REPO_ROOT`. Parent CWD drifted off the intended repo; never `cd`-fix (doesn't propagate). Not a `--resume` candidate (no work done). |
| §preflight-shared gate 1–3 | Refuse + surface failing gate. |
| §phase-1b worktree creation fail (`git worktree add` errored, or step-2 verify failed) | Stop before spawning agent. `git worktree remove` if partial; release consumer-defined lock. Not a `--resume` candidate. |
| §phase-1d verify fail | Stop; `--resume`. Treat as worktree-invariant breach. |
| Agent `stopped:worktree-isolation-failed` | Sub-agent failed its first-call `cd` or post-cd verify (no edits made). Teardown: remove worktree + branch + release consumer lock. Not a `--resume` candidate. |
| Agent `stopped:empty-result` (no commits) | Same teardown as `worktree-isolation-failed`. Not a `--resume` candidate. |
| Agent `stopped:*` / crash (other) | Stop; `--resume`. |
| §phase-1d scope gate trips | Surface shortstat to user; user answers `proceed` or `abort` (parent removes worktree + branch on abort). |
| Refine `daemon_unhealthy` | Stop; surface `roborev status` output. |
| Refine `flapping` / `stopped:*` / crash | Stop; `--resume` or §phase-2-broadening. |
| Phase-2 worktree re-verify fail | Stop; `--resume`. |
| Tiebreaker 1, 2, 4 (finding) | Auto-disposed in-flight from evidence; no parent ask (§Mechanic). A re-gating consumer (e.g. prompt-ship) asks instead. |
| Tiebreaker 3 (rebase conflict), 5 | Agent returns packet → parent asks → respawn continuation with disposition (§Mechanic). |
| Tiebreaker 4 | Consumer-defined `TIEBREAKER_4` flow. |
| Rebase conflict `rerere` can't clear | Tiebreaker 3. |
| §phase-3 `stopped:test_lint_fail` | Manual fix in worktree + `--resume`. |
| Squash `fell_back` | Ship agent continues un-squashed; note in report. |
| ff-only rejected twice | Stop; `--resume`. |

Consumer skills extend this table with rows specific to their
work-source, lock, or close step.

---

## Consumers (inverse pointer — keep current)

- `/kata-ship` — kata-driven; uses kata short_id, kata.owner lock,
  `/kata-resolve` for Phase 1, `KATA_PUSH:` for tiebreaker 4,
  `kata close` for `CLOSE_STEP`.
- `/prompt-ship` — prompt-driven; uses 8-char uuid identity,
  branch+`.run-prompt/PROMPT.md` as lock, verbatim user prompt for
  Phase 1, `fix-now / defer / false-positive` for tiebreaker 4,
  echo-only `CLOSE_STEP`.

When adding a future ship-variant: pick `EXPECTED_REPO_BASENAME` /
`SHORT_ID` / `LOCK_ANCHOR` / `TIEBREAKER_4` / `CLOSE_STEP`; cite the
anchors above (including §repo-anchor); add a row to this list.

When modifying any anchor in this file: search consumer SKILL.md
files for the anchor name and update them in the same change.
