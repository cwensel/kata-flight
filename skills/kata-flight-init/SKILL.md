---
name: kata-flight-init
argument-hint: [--workspace] [--context-root <path>] [--rdr-home <path>]
description: 'Use to bind a consumer repo to Kata Flight: create or refresh .kata-flight seam, env/resources files, optional workspace marker, and optional RDR binding. Trigger for set up kata-flight or $kata-flight-init.'
---

# kata-flight-init

Bind the current consumer repository to Kata Flight.

Run from the repository that owns the code and kata tracker. Do not run from the
Kata Flight skill repo itself or from the RDR engine repo.

## Usage

```sh
/kata-flight-init
/kata-flight-init --workspace
/kata-flight-init --context-root <path>
/kata-flight-init --rdr-home <path>        # non-standard or ambiguous RDR home
/kata-flight-init --context-root <path> --rdr-home <path>
```

## Procedure

1. Confirm the current directory is a git repository:

   ```sh
   git rev-parse --show-toplevel
   ```

2. Resolve the engine root — the parent of the `skills/` dir holding this skill
   (`ENGINE_ROOT`). The cwd is the consumer repo, not the engine, so use the
   installed skill path, never a bare relative path.

3. Run the bundled init script from `ENGINE_ROOT`:

   ```sh
   "$ENGINE_ROOT/scripts/flight-init.sh" [--workspace] [--context-root <path>] [--rdr-home <path>]
   ```

   When `--context-root` is omitted, a parent `$WS/.rdr-workspace` can supply the
   default context root from its `RDR_RESOURCES` path when that root has
   `context/rdr-resources.md` and `rdr/evidence/`. Otherwise the consumer repo is
   the context root. When `--rdr-home` is omitted, the script checks the two
   canonical workspace locations: `$WS/rdr` and `$WS/process/rdr`. It binds RDR
   automatically only when exactly one candidate has `stages/`, `skills/`,
   `prompts/`, and `TEMPLATE.md`. Use `--rdr-home` for non-standard paths or if
   both canonical candidates are valid.

4. Verify the seam contract:

   ```sh
   PROJECT=$(git rev-parse --show-toplevel)
   WS=$(dirname "$PROJECT")
   if   [ -f "$PROJECT/.kata-flight/workspace" ]; then . "$PROJECT/.kata-flight/workspace"
   elif [ -f "$WS/.kata-flight-workspace" ]; then . "$WS/.kata-flight-workspace"
   else echo "stopped:no-kata-flight-marker"; fi
   [ -d "$KATA_FLIGHT_HOME" ] || echo "stopped:kata-flight-home"
   [ -d "$KATA_FLIGHT_CONSUMER_ROOT" ] || echo "stopped:consumer-root"
   [ -f "$KATA_FLIGHT_ENV" ] || echo "stopped:env"
   [ -f "$KATA_FLIGHT_RESOURCES" ] || echo "stopped:resources"
   if [ -n "${KATA_FLIGHT_RDR_HOME:-}" ]; then
     [ -d "$KATA_FLIGHT_RDR_HOME/stages" ] || echo "stopped:rdr-home"
   fi
   ```

5. Report the marker path plus `KATA_FLIGHT_EXPECTED_REPO_BASENAME`,
   `KATA_FLIGHT_CONTEXT_ROOT`, `KATA_FLIGHT_ENV`, `KATA_FLIGHT_RESOURCES`,
   and the auto-detected or explicit `KATA_FLIGHT_RDR_HOME` when present.

## Seam Shape

Default scope is repo-local: `.kata-flight/workspace`. `--workspace` writes a
shared marker at the parent workspace: `.kata-flight-workspace`. Consumers should
resolve nearest-wins: repo-local first, workspace marker second. If a parent RDR
seam exists, Kata Flight inherits its project evidence context by default and
adds Kata-specific runtime/research routes in `.kata-flight/resources.md`.

The generated files mirror the RDR init pattern:

- `.kata-flight/workspace` — sourceable marker consumed by skills.
- `.kata-flight/env.md` — human-readable path map.
- `.kata-flight/resources.md` — runtime requirements plus optional research
  corpus routes.
- `.kata-flight/env` — compatibility shim that sources the marker.
- `.kata-flight/.gitignore` — ignores the per-machine seam without touching the
  consumer repo's root `.gitignore`.

## Reference Files

`flight-init.sh` generates the live seam; these engine-root files are references:

- [`workspace.example`](../../workspace.example) — the marker contract (the
  `KATA_FLIGHT_*` variables a marker exports). For reading or hand-authoring.
- [`kata-flight-seam-context.sh.template`](../../kata-flight-seam-context.sh.template)
  — optional `SessionStart` hook that pre-resolves the seam. Not installed
  automatically; on request, copy to `.claude/hooks/` (Claude) or `.codex/hooks/`
  (Codex), wire a `SessionStart` hook in settings, and trust-review via `/hooks`.

## RDR Binding

RDR is optional. Init auto-detects the two canonical workspace locations:
`$WS/rdr` and `$WS/process/rdr`. If exactly one is a valid RDR engine checkout,
it writes `KATA_FLIGHT_RDR_HOME` automatically. Pass `--rdr-home <path>` only
for non-standard paths or if both canonical candidates are valid. Do not clone
RDR without explicit user permission. If no RDR home is bound, kata-only skills
still work; RDR-specific skills must stop and ask the user to rerun
`/kata-flight-init --rdr-home <path>` before they rely on RDR resources.

## Research Resources

The resources file records whether Arcaneum corpus discovery was available at
init time, but it does not select corpora automatically. Treat corpora as
explicit, task-specific reference routes for RDR/citation work, not as Kata
Flight runtime dependencies. Before adding a quote or citation to a kata, RDR,
or skill, open the source result and anchor it by title plus DOI, arXiv, URL, or
page. Use `arc corpus list` and user/agent judgment to choose task-relevant
project, standards, code, or paper corpora.
