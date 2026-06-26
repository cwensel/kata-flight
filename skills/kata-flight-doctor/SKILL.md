---
name: kata-flight-doctor
argument-hint: (none - run from any consumer repo/worktree)
description: 'Use to verify a Kata Flight setup. Read-only health check for the .kata-flight seam, marker vars, engine layout, context root, optional RDR binding, and skill links. Trigger for diagnose Kata Flight, check Kata Flight setup, $kata-flight-doctor, or /kata-flight-doctor.'
---

# kata-flight-doctor

Read-only health check for a consumer repo bound by `kata-flight-init`.
It writes nothing and keeps running after failures so the report shows every
broken invariant plus the one repair command.

## Run it

Run the bundled script file beside this `SKILL.md`; do not paste its body:

```sh
GC=$(git rev-parse --git-common-dir 2>/dev/null) && GC=$(cd "$GC" && pwd -P)
WS=$(dirname "$(dirname "$GC")")
for H in "$KATA_FLIGHT_HOME" "$CLAUDE_PLUGIN_ROOT" "$CODEX_PLUGIN_ROOT" "$WS/kata-flight"; do [ -f "$H/skills/kata-flight-doctor/doctor.sh" ] && { sh "$H/skills/kata-flight-doctor/doctor.sh"; break; }; done
```

Under Codex, if the environment vars are unset, run the `doctor.sh` that sits
beside this filesystem-backed skill.

Print the script stdout verbatim inside a fenced block. Do not reformat it.
If a line says FAIL, surface its fix as-is.

## Next Step

- All PASS -> `Next: /kata-flow-ops`, `/kata-flight <selector>`, or
  `/kata-flight-init` only when rebinding deliberately.
- Any FAIL -> run the named fix, usually `/kata-flight-init`, then re-run
  `/kata-flight-doctor`.
