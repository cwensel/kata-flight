---
name: kata-resolve
argument-hint: <short-id…> [--no-lock-mgmt]
description: 'Use to resolve, fix, or work on one or more kata issues in a consumer repo. Reads kata state, works in isolation, commits a fix, and closes/comments as appropriate. Trigger for resolve/fix kata or $kata-resolve.'
---

# kata-resolve

Drop-in playbook for resolving one or more issues tracked in kata.

## Usage

```
/kata-resolve <short-id> [<short-id> ...]
/kata-resolve <short-id> --no-lock-mgmt
```

Without arguments: ask the user which issue(s) to start with, or run
`kata ready --json` and pick the first open, unblocked one.

`--no-lock-mgmt` is set by callers (notably `/kata-ship`) that own
the kata lock themselves. It mechanically skips step 2's `kata
assign` + `kata label add lifecycle:resolving` *and* step 7's `kata close` +
`kata label rm lifecycle:resolving`. The fix commit and the `kata comment`
summarizing it still happen. Use only when another skill is actively
managing ownership; never set it for a direct user invocation.

## When NOT to invoke this skill

A pasted issue body is not itself a request to resolve. Invoke only when
the user explicitly says `/kata-resolve`, names issue numbers and asks to
fix them, or asks for "the next kata issue." For "what is kata #42
about?" use `kata show 42` and answer normally.

## IMPORTANT

You must **execute bash commands** to complete this task. The kata CLI is
the source of truth for status — always `kata show <N>` before acting on
a number from memory or chat. Defer to CLAUDE.md when it conflicts.

## Brevity

Be brief without being lossy. Applies to issue bodies/comments (drop
empty or obvious sections; a reproducer is one shell block, not a
narrative) and status reports (no recap of steps the user just watched,
no "I'll now…" scaffolding; cite numbers and short hashes).

Root cause, invariant, blocker, follow-up issue — these stay.

## Read first, code second

- `kata show <N> --json` — note status, labels (`severity:*`, `area:*`),
  comments, and links. **Read labels from the top-level `.labels[]`**
  (objects with `.label` on `show`; bare strings on `kata list`);
  `.issue.labels` is NULL — never read it (corpus: drab). If `<N>`
  blocks-on something open, surface to the user before starting.
- **`kind:rdr-seed` is a hard stop.** If labels include `kind:rdr-seed`,
  refuse with `stopped:rdr-seed` before any worktree, ownership, or file
  read. Deliverable is an RDR draft (umbrella kata dtr1) — no red/green
  test pair, no code change directly. Surface that activation requires
  human direction (slot allocation, design-question resolution, or
  upstream RDR lock); offer `kata show <N>` for read-only inspection.
- `context/project-guidelines.md` — project conventions and resolution
  patterns (read via `$KATA_FLIGHT_CONTEXT_ROOT`; see step 1). Cite the relevant
  bullet in the commit body if it shaped the fix.
- `git log --oneline -10` for recent commit shape.
- Skim the file paths the issue body names ("Affected code" line) before
  touching anything else. If a line number is present, use it only to find the
  nearby comment block once; if it is stale, anchor by symbol/nearby text and
  move on. Do not repair line numbers in kata comments. When code is wrong on
  purpose, the nearby comment usually names the helper, sibling kata, or
  precedent that owns the fix.
- Do not resolve a kata by re-anchoring line-only references after unrelated
  drift. This includes test fixtures, allowlists, snapshots, and review/census
  maps keyed as `path:line`: treat the line as a locator hint, then prove the
  current behavior by symbol/nearby text/git history. Update a line-keyed entry
  only when the kata is explicitly about line semantics or the underlying
  behavior changed; otherwise leave the stale anchor alone and fix the real
  issue.
- For every `kata <slug>` / `RDR <id>` cited in the body: `kata show
  <slug>` + `git log --grep=<slug> --oneline` before deciding shape.
  Cited precedents transfer near-verbatim more often than not.

## How to resolve an issue

1. **Work in an isolated worktree (mandatory).** Before any file read
   or edit, ensure you are inside a worktree for `<N>`. Run:

   ```sh
   GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
   GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
   ```

   If `GIT_DIR != GIT_COMMON` you are already in a worktree; reuse it.

   If `GIT_DIR == GIT_COMMON`:

   - **Under `--no-lock-mgmt`** (invoked from `/kata-ship` as a
     sub-agent), the caller has already pre-created the worktree but
     the brief expected the sub-agent to `cd` into it. Refuse with
     `stopped:worktree-cd-missing` — the sub-agent skipped its first
     Bash call (`cd <worktree_path>`). Do **NOT** invoke
     `using-git-worktrees` or call `EnterWorktree` — a sub-agent cannot
     create a worktree (the harness refuses **both** `EnterWorktree(name:)`
     and `EnterWorktree(path:)` from a cwd-pinned context; see
     worktree-ship-pipeline §worktree-creation-rationale), and
     `using-git-worktrees` would try to. The parent already created it;
     just `cd` in.

   - **Without `--no-lock-mgmt`** (direct user invocation), create the
     worktree with a raw Bash `git worktree add` and `cd` into the
     result before doing anything else — **not** `EnterWorktree` or
     `using-git-worktrees`. Raw `git worktree add` is the only mechanism
     that works whether this invocation runs at L0 or is itself spawned
     into a pinned context (§worktree-creation-rationale).

   The primary checkout MUST stay on its current branch while you
   work. Never `git checkout -b` in the primary repo. Refuse to
   proceed if the user explicitly asks to work in place — direct
   them to `kata show <N>` for read-only inspection instead.

   **Establish `PRIMARY_ROOT` and `KATA_FLIGHT_CONTEXT_ROOT`.** Derive the primary
   checkout from the common git dir (already computed above), then the
   configured Kata Flight context root that holds the consolidated resources:

   ```sh
   PRIMARY_ROOT=$(dirname "$GIT_COMMON")   # primary checkout; == cwd when not in a worktree
   [ -f "$PRIMARY_ROOT/.kata-flight/env" ] && . "$PRIMARY_ROOT/.kata-flight/env"
EXPECTED_REPO_BASENAME="${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-$(basename "$PRIMARY_ROOT")}"
[ "$(basename "$PRIMARY_ROOT")" = "$EXPECTED_REPO_BASENAME" ] || { echo "stopped:wrong-repo:$PRIMARY_ROOT" >&2; exit 1; }
   WS=$(dirname "$PRIMARY_ROOT")   # workspace root (worktree-invariant via $GIT_COMMON)
   KATA_FLIGHT_CONTEXT_ROOT="${KATA_FLIGHT_CONTEXT_ROOT:-$PRIMARY_ROOT}"
   if   [ -f "$PRIMARY_ROOT/.kata-flight/workspace" ]; then . "$PRIMARY_ROOT/.kata-flight/workspace"; elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"; fi
   [ -d "$KATA_FLIGHT_CONTEXT_ROOT" ] || { echo "stopped:context-root-not-found:$KATA_FLIGHT_CONTEXT_ROOT" >&2; exit 1; }
   ```

   `PRIMARY_ROOT` is still the work repo — the skill operates on
   consumer code, so the configured repository-name assert stays. The basename assert
   catches a worktree created in the wrong sibling repo (`process`,
   other sibling repositories) — `dirname $GIT_COMMON` derives the root from
   git topology, so it's correct for *whatever* repo this is a worktree
   of; the assert confirms it's the intended one.

   **Read all resources through `$KATA_FLIGHT_CONTEXT_ROOT`.** The project conventions,
   RDR resources, and critiques used to live in the consumer repository gitignored
   `_guidelines/` and `_rdr/` dirs; they have been consolidated into the
   configured Kata Flight context root, where they are **tracked** under `context/` and
   `rdr/evidence/`. Read them through `$KATA_FLIGHT_CONTEXT_ROOT`, e.g.
   `$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md`,
   `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/critique/<NNNN-slug>-critique.md`. This is
   the configured RDR evidence root, not the external RDR methodology repo.
   Because `KATA_FLIGHT_CONTEXT_ROOT` is derived from the worktree's git topology (the
   primary checkout's sibling), not from this skill file's location, the
   reads resolve whether this is the installed Kata Flight skill or a
   symlink invoked from a consumer worktree.

2. **Take ownership on open.** Before any other work on `<N>`, assign it
   to yourself and mark its lifecycle state so concurrent sessions don't
   double-up (standalone mode only — under `kata-ship` the caller already
   owns the `lifecycle:*` phase label):

   ```sh
   kata assign <N> "$(kata whoami --json | jq -r .actor)" --json
   kata label add <N> lifecycle:resolving --json   # see the consumer label vocabulary reference
   ```

   When invoked standalone (not under `--no-lock-mgmt`), this skill runs as
   a leaf agent per `worktree-ship-pipeline` §leaf-agent-contract (verdict-only).

   **Skip this entire step under `--no-lock-mgmt`** — the caller (e.g.
   `/kata-ship`) already owns the kata under its own synthetic id
   (`kata-ship/<id>`), and a `kata assign` here would overwrite the
   lock with the human actor and silently dissolve cross-session
   coordination.

   **Safety net.** Even without the flag, before calling `kata
   assign`, read `kata show <N> --json | jq -r .issue.owner`. If the
   current owner matches `^kata-ship/` (or any other agent-prefixed
   value), do **not** assign — refuse and tell the user:

   > "kata `<N>` is held by ship session `<owner>` (label
   > `lifecycle:resolving|refining|shipping`). Use `/kata-ship --resume
   > <N>` to recover; do not resolve directly on a ship-locked kata."

   Otherwise, if owned by a different human or already labeled
   `lifecycle:resolving`, surface that to the user before continuing.

3. **Reproduce first.** If the issue body has a reproducer, run it. Confirm
   the failure mode is what the body describes. If the symptom drifted
   (the bug got worse, masked, or partially fixed by an earlier commit),
   `kata comment <N>` with the live observation before changing code, so
   the trail reflects current reality.

4. **Gauge complexity; ultrathink if non-trivial.** Trivial paths
   (help-text, hint phrasing, typo, mechanical rename) skip ahead.
   Otherwise trigger ultrathink and read cited code + RDR + related
   issues + principles before writing the test (RDR/critiques via
   `$KATA_FLIGHT_CONTEXT_ROOT/rdr/evidence/...`, conventions via
   `$KATA_FLIGHT_CONTEXT_ROOT/context/project-guidelines.md`). Triggers: multi-claim
   issues, framing-vs-RDR tension, cross-subsystem reach, structural
   changes (new abstraction, parity-test removal, audit-boundary moves),
   ambiguous disposition, or round-trip/closure/hash-stability invariants
   where a wrong call corrupts artifacts silently.

   **Three "stop and ask" verdicts. Pick the right one — they route
   differently.**

   - `stopped:complex-rdr-implementation` — no precedent cited, no helper
     to mirror; design call needed. Before emitting, confirm: (a) no
     cited kata / RDR / bypass comment names the fix pattern, (b) `git
     grep` for named helpers returns no parallel. Failing either →
     follow the precedent.

   - `stopped:precedent_unread:<slugs>` — you must stop but you didn't
     read the named precedent yet; next session picks up there.

   - `stopped:needs-triage:<one-phrase>` — precedent IS cited and the
     body IS specific, but read-first revealed (1) the precedent's
     structural preconditions don't exist at the target seam (e.g.
     cited pattern consumes `[]*op.Instance`; this seam has no op
     stream), or (2) the named call sites split into structural
     classes needing different fixes (different forests, mint timings,
     return types). Emit BEFORE any edit; worktree empty. Carry the
     question in `resolve_intent_excerpt` (≤80 words): what's ambiguous
     + what answers unblock. Don't pick an approach or split the kata
     yourself.

5. **Red/green TDD.** Failing test locking the invariant first, then
   green. Stays as a regression guard. Start from the issue body's
   "Regression-test plan."

6. **One commit per issue (parent repo).** Conventional Commits
   (`fix(cli): …`, `feat(cli): …`). Reference the kata issue in the body
   (`Fixes kata #N`). Body restates root cause, describes the fix
   mechanism (not just files changed), records non-obvious context
   (invariants preserved, alternatives rejected), and notes follow-up
   issues. Never attribute to Claude / AI / Co-Authored-By. ~150–300
   words typical; less for trivial.

   **Pre-commit scope check.** Run `git diff --stat --staged`. Every
   changed/deleted file must map to a path the kata body names, a
   direct test of it, or a caller the named edit forces. Anything
   else → unstage and route via step 8. Title-only commits only for
   ≤3-file fixes with no deletions or renames; any deletion or
   off-named-path edit gets one body line per file naming why it had
   to move with the fix.

   **Never weaken an unrelated test to make a build pass.** If a broad
   `go test ./...` surfaces a *pre-existing, unrelated* failure, it is
   not yours to fix — scope your verification run to the package(s) you
   touched (`-run` filter or `./internal/<pkg>/...`) and note the
   unrelated failure, do not relax its assertions / delete its helpers /
   loosen its guards to get green. (When invoked from `/kata-ship`, the
   parent inlines `worktree-ship-pipeline` `§scope-discipline` in your
   brief and the §phase-1d gate verifies the committed diff against your
   reported `in_scope_paths`; this clause is the same rule, restated
   for the standalone path. Recurring evidence: kata 0bek / 2tx8.)

7. **Close the kata issue — drive to closure.** Once committed and tests
   green, close immediately. Verify the fix with the test suite (and any
   reproducer from step 3), then:

   ```sh
   kata label rm <N> lifecycle:resolving --json
   kata close <N> --done --commit <short-hash> \
     --message "Resolved: <scope + how verified — ≥40 chars>" --json
   ```

   `kata close` requires a substantive `--message` (≥40 chars) **and** typed
   `--evidence` — use `--commit <sha>` sugar. A bare `kata close --reason
   done` fails validation; the `--message` is the close's record (no separate
   `kata comment` needed).

   **Read-back-verify state changes.** `kata label add` / `kata close`
   can exit 0 without persisting. After the close, re-read and confirm
   `status == "closed" && owner == null` rather than trusting the exit;
   after any `kata label add` / `rm`, re-read the top-level `.labels[]`
   (objects on show, never `.issue.labels`) to confirm it landed.
   Re-issue on mismatch (corpus: m3sd / drab).

   Clearing `lifecycle:resolving` applies on every terminal disposition
   (`done`, `wontfix`, or leave-open) — the label tracks active work, not
   disposition.

   **Under `--no-lock-mgmt`**, run only the `kata comment` line. Skip
   the label rm (the caller's `lifecycle:*` is the real lock) and skip
   `kata close` (the caller closes after merge). The commit-summary
   comment is still posted — it complements ship's phase-transition
   comments, not duplicates them.

   Defer closure only on a real blocker (RDR pending, follow-up issue
   blocking) — leave the kata in its `lifecycle:*` state, comment why,
   and (if the blocker is another kata) `kata edit <N> --blocked-by
   <blocker>` so `kata ready` reflects it. For wontfix, use `--reason
   wontfix` and put the explanation in the comment. The comment replaces
   the old issue file's "Resolution" section — explain *why* this
   disposition, especially when rejecting the issue's framing.

8. **File new issues you uncover.** Don't bundle a separate latent bug
   into the current commit. Search first:

   ```sh
   kata search "<keyword>" --json
   ```

   Then create:

   ```sh
   kata create "<one-line title>" \
     --body-file /tmp/issue-body.md \
     --label type:bug \
     --label area:<subsystem> \
     --label severity:<level> \
     --label lifecycle:filed \
     --idempotency-key "<deterministic-key>" \
     --json
   ```

   `lifecycle:filed` stamps it into the backlog (not yet ship-ready);
   triage/scope-review later replaces it with `lifecycle:queued` (single-valued
   — transition=replace; see the consumer label vocabulary reference), and
   `kata ready --label lifecycle:queued` is the standing drain queue.

   Link with `kata edit <new-N> --related <N>` for follow-ons, or
   `kata edit <new-N> --blocks <N>` when the new bug blocks the original
   (so `kata ready` reflects it). Edit the just-created `<new-N>` so the
   idempotency-key'd `create` above stays untouched.

## Issue body skeleton (when filing new issues)

```markdown
## What's broken
What the user sees vs what they expect.

## Reproducer
Shell session that triggers the bug. Verify it actually triggers before filing.

## Root cause (or "Why this is suspected")
Where the bug lives in the code, and why. If you haven't confirmed it, say so.

## Why no test caught it
What the existing test surface assumes that the bug violates.

## Suggested fix sketch
Code shape, not a full patch. Note open questions.

## Related
Cross-references to other kata issues, RDRs, or commits.

## Regression-test plan
Bullet list of tests to add when the fix lands.

## DX context (optional)
The workflow that surfaced it, if relevant.
```

Apply labels at create time:

- `severity:trivial|low|medium|high` — see heuristic below.
- `area:<subsystem>` — `area:import`, `area:snapshot`, `area:drift`,
  `area:op-add`, `area:op-revise`, `area:resolver`, `area:catalog`,
  `area:cli`, `area:create`, `area:rdr`, `area:reconcile`, `area:lint`,
  `area:genealogy`, `area:seal`. Pick from existing labels first
  (`kata labels`), invent new ones only when truly novel.
- `lifecycle:filed` — stamps it into the backlog (not yet ship-ready).
- `type:bug` (or the matching `type:*`) — one per kata.

A real-but-blocked issue isn't a label: leave it `lifecycle:filed` and
record the blocker with `kata edit <N> --blocked-by <blocker>` so `kata
ready` excludes it until the blocker clears (the old bare `deferred` /
`phase-1-resolved` labels were killed in the namespace migration —
the consumer label vocabulary reference).

## Severity heuristic

- **High**: silently corrupts state (oplog, registry, on-disk artifact);
  user has no indication.
- **Medium**: blocks a documented workflow; user can work around but the
  workaround is ugly or non-obvious.
- **Low**: friction, prose, or hint quality. Doesn't block; degrades
  polish.
- **Trivial**: docs/typo. Pure ergonomic.

When you set a `severity:` label, **also set `--priority`** — priority is a
separate scalar field (`0..4`, 0 = highest) and is what ordering reads; the
severity label is not. Use the `severity:` → priority table in
the consumer label vocabulary reference (default: high→P1, medium→P2, low→P3,
trivial→P4; P0 reserved for reachable data-safety/security).

## Project conventions and resolution patterns

Canonical reference: **`context/project-guidelines.md`** (via
`$KATA_FLIGHT_CONTEXT_ROOT` — step 1) — code-architectural invariants (CLI structure,
catalog wiring, vertex-hash update sites, drift's audit boundary, …) and
resolution patterns (triage filters, implementation recipes). Skim
before any non-trivial resolution; cite the bullet in the commit body
when it shaped the fix.

## Self-update

When a resolution teaches something a future session needs:

- **Engineering knowledge** (convention, gotcha, vocabulary distinction,
  debug technique, triage filter, implementation pattern) → terse bullet
  to `context/project-guidelines.md` (in `$KATA_FLIGHT_CONTEXT_ROOT`).
- **Workflow change** (this skill's playbook should do differently) →
  update this file.

Specific bug details belong in the kata issue + commit, not here.
One-time decisions don't belong here either.

## Auto mode

Multiple issue numbers: work in order, commit each as you go (parent-repo
fix + `kata close`). New bug surfaces → file it (step 8) and move on.
Course-correct between issues if anything looks off. Tell the user which
issue you're starting with and proceed.

`--no-lock-mgmt` is intended for single-issue invocations from a wrapper
skill that owns the lock for that one kata. Multi-issue + `--no-lock-mgmt`
is not a supported combination — the lock semantics don't fan out. If a
wrapper needs to drive several katas, it invokes `/kata-resolve` once per
kata, holding its own lock around each call.
