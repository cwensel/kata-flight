#!/bin/sh
# kata-flight-doctor - read-only Kata Flight seam/engine health check.
# POSIX sh. Run as a file: sh "$THIS".

GC=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "[FAIL] not in a git repo - run \$kata-flight-doctor in Codex or /kata-flight-doctor in Claude inside a consumer repo"; exit 0; }
GIT_COMMON=$(cd "$GC" && pwd -P) || { echo "[FAIL] git dir unreadable"; exit 0; }
PROJECT=$(dirname "$GIT_COMMON")
WS=$(dirname "$PROJECT")
export PROJECT WS

echo "kata-flight-doctor - project: $PROJECT"
nf=0
nw=0
fail(){ echo "  [FAIL] $1"; nf=$((nf+1)); }
warn(){ echo "  [WARN] $1"; nw=$((nw+1)); }
pass(){ echo "  [PASS] $1"; }

if   [ -f "$PROJECT/.kata-flight/workspace" ]; then MARKER="$PROJECT/.kata-flight/workspace"; SCOPE="repo-local"
elif [ -f "$WS/.kata-flight-workspace" ]; then MARKER="$WS/.kata-flight-workspace"; SCOPE="workspace (shared)"
else
  fail "1 no marker - run \$kata-flight-init in Codex or /kata-flight-init in Claude in this repo"
  echo "Verdict: 1 FAIL - no marker."
  exit 0
fi
pass "1 marker present - $MARKER  [$SCOPE]"

ERR="${TMPDIR:-/tmp}/kata-flight-doctor.err.$$"
. "$MARKER" 2>"$ERR" && pass "2 marker sources clean" || fail "2 marker source error - $(head -1 "$ERR")"

m=""
for v in KATA_FLIGHT_HOME KATA_FLIGHT_CONSUMER_ROOT KATA_FLIGHT_EXPECTED_REPO_BASENAME KATA_FLIGHT_CONTEXT_ROOT KATA_FLIGHT_ENV KATA_FLIGHT_RESOURCES; do
  eval "[ -n \"\${$v:-}\" ]" || m="$m $v"
done
[ -z "$m" ] && pass "3 required vars set" || fail "3 unset:$m - re-run \$kata-flight-init in Codex or /kata-flight-init in Claude"

[ -d "${KATA_FLIGHT_HOME:-}/skills" ] && [ -f "${KATA_FLIGHT_HOME:-}/scripts/flight-init.sh" ] && pass "4 engine resolves - $KATA_FLIGHT_HOME" || fail "4 KATA_FLIGHT_HOME is not an engine root (${KATA_FLIGHT_HOME:-}) - re-run /kata-flight-init"

[ -d "${KATA_FLIGHT_CONSUMER_ROOT:-}" ] && pass "5 consumer root - $KATA_FLIGHT_CONSUMER_ROOT" || fail "5 consumer root missing (${KATA_FLIGHT_CONSUMER_ROOT:-}) - re-run /kata-flight-init"
[ -d "${KATA_FLIGHT_CONTEXT_ROOT:-}" ] && pass "6 context root - $KATA_FLIGHT_CONTEXT_ROOT" || fail "6 context root missing (${KATA_FLIGHT_CONTEXT_ROOT:-}) - re-run /kata-flight-init --context-root PATH"

if [ -n "${KATA_FLIGHT_EXPECTED_REPO_BASENAME:-}" ]; then
  [ "$(basename "$PROJECT")" = "$KATA_FLIGHT_EXPECTED_REPO_BASENAME" ] && pass "7 expected repo basename matches" || fail "7 wrong repo basename - expected $KATA_FLIGHT_EXPECTED_REPO_BASENAME, got $(basename "$PROJECT"); run from the bound repo or re-run /kata-flight-init"
else
  fail "7 expected repo basename unset - re-run /kata-flight-init"
fi

[ -f "${KATA_FLIGHT_ENV:-}" ] && [ -f "${KATA_FLIGHT_RESOURCES:-}" ] && pass "8 env/resources files exist" || fail "8 missing KATA_FLIGHT_ENV/KATA_FLIGHT_RESOURCES - re-run /kata-flight-init"
if [ -f "$PROJECT/.kata-flight/.gitignore" ]; then
  pass "9 seam gitignore present"
else
  warn "9 no .kata-flight/.gitignore - re-run /kata-flight-init to keep the seam out of git"
fi
if [ "$SCOPE" = "repo-local" ]; then
  [ -f "$PROJECT/.kata-flight/env" ] && pass "10 compatibility env shim present" || warn "10 no .kata-flight/env shim - re-run /kata-flight-init to refresh compatibility files"
else
  [ -f "$PROJECT/.kata-flight/env" ] && pass "10 compatibility env shim present" || echo "  [INFO] 10 no repo-local env shim for workspace marker - n/a"
fi

if [ -n "${KATA_FLIGHT_RDR_HOME:-}" ]; then
  [ -d "$KATA_FLIGHT_RDR_HOME/stages" ] && [ -d "$KATA_FLIGHT_RDR_HOME/skills" ] && [ -d "$KATA_FLIGHT_RDR_HOME/prompts" ] && [ -f "$KATA_FLIGHT_RDR_HOME/TEMPLATE.md" ] && pass "11 optional RDR binding resolves - $KATA_FLIGHT_RDR_HOME" || fail "11 KATA_FLIGHT_RDR_HOME is not an RDR engine ($KATA_FLIGHT_RDR_HOME) - re-run /kata-flight-init --rdr-home PATH"
else
  warn "11 no optional RDR binding - RDR-backed skills will stop until /kata-flight-init --rdr-home PATH"
fi

b=$(find "${KATA_FLIGHT_HOME:-}/skills" -type l ! -exec test -e {} ";" -print 2>/dev/null)
[ -z "$b" ] && pass "12 engine skill symlinks resolve" || { fail "12 broken engine symlinks - reinstall or refresh Kata Flight:"; echo "$b" | sed "s/^/        /"; }

seen12=
for base in "$PROJECT/.claude/skills" "$PROJECT/.codex/skills"; do
  [ -d "$base" ] || continue
  seen12=1
  b=$(find "$base"/kata-* "$base"/rdr-* "$base"/roborev-triage "$base"/prompt-ship "$base"/worktree-ship-pipeline 2>/dev/null | while IFS= read -r p; do [ -L "$p" ] && [ ! -e "$p" ] && printf '%s\n' "$p"; done)
  [ -z "$b" ] && pass "13 consumer links resolve - $base" || { fail "13 broken consumer links in $base - repoint to \$KATA_FLIGHT_HOME/skills/:"; echo "$b" | sed "s/^/        /"; }
done
[ -n "$seen12" ] || echo "  [INFO] 13 no consumer skill links here - n/a"

command -v kata >/dev/null 2>&1 && pass "14 kata CLI available" || warn "14 kata CLI not on PATH - install kata before shipping"
command -v roborev >/dev/null 2>&1 && pass "15 roborev CLI available" || warn "15 roborev CLI not on PATH - review/refine skills will fail"

rm -f "$ERR"
if [ "$nf" -gt 0 ]; then
  echo "Verdict: $nf FAIL, $nw WARN - fix the FAIL(s) above, then re-run \$kata-flight-doctor in Codex or /kata-flight-doctor in Claude."
elif [ "$nw" -gt 0 ]; then
  echo "Verdict: 0 FAIL, $nw WARN - healthy; WARNs are advisory."
else
  echo "Verdict: all checks PASS - the Kata Flight seam is healthy."
fi
