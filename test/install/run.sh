#!/usr/bin/env bash
# Verify Kata Flight installs as documented in the README, in a clean container.
# Exercises the real `claude plugin` and `codex plugin` CLIs. No model auth is
# needed for marketplace-add / install / list (they manipulate local config).
#
# Override the repo under test with KF_REPO (default: cwensel/kata-flight).
set -uo pipefail

REPO="${KF_REPO:-cwensel/kata-flight}"          # GitHub repo for the Claude install
fail=0
section() { printf '\n========== %s ==========\n' "$1"; }
ok()   { printf '  [PASS] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=1; }

section "Versions"
claude --version || bad "claude --version"
codex --version  || bad "codex --version"

# --- Claude: marketplace add + install, exactly as the README documents -------
section "Claude: /plugin marketplace add $REPO"
if claude plugin marketplace add "$REPO" 2>&1; then ok "marketplace add"; else bad "marketplace add"; fi

section "Claude: marketplace list (should show kata-flight)"
claude plugin marketplace list 2>&1 | tee /tmp/cl-mkt.txt
grep -q "kata-flight" /tmp/cl-mkt.txt && ok "kata-flight marketplace present" || bad "kata-flight not listed"

section "Claude: /plugin install kata-flight@kata-flight"
if claude plugin install kata-flight@kata-flight 2>&1; then ok "install"; else bad "install"; fi

section "Claude: plugin list (should show kata-flight installed)"
claude plugin list 2>&1 | tee /tmp/cl-list.txt
grep -q "kata-flight" /tmp/cl-list.txt && ok "kata-flight installed" || bad "kata-flight not installed"

section "Claude: validate the cloned plugin manifest directly"
rm -rf /tmp/kf && git clone --depth 1 "https://github.com/$REPO" /tmp/kf 2>&1 | tail -1
if claude plugin validate /tmp/kf 2>&1; then ok "claude plugin validate"; else bad "claude plugin validate"; fi

# The symlink that makes the Codex .agents marketplace resolve must survive a clone.
section "Codex symlink contract: plugins/kata-flight -> repo root"
if [ -e /tmp/kf/plugins/kata-flight/.codex-plugin/plugin.json ]; then
  ok "plugins/kata-flight/.codex-plugin/plugin.json resolves"
else
  bad "plugins/kata-flight symlink broken in fresh clone"
fi

# --- Codex: marketplace add (local path) + add, as the README documents -------
section "Codex: plugin marketplace add <path>"
if codex plugin marketplace add /tmp/kf 2>&1; then ok "codex marketplace add"; else bad "codex marketplace add"; fi

section "Codex: plugin list"
codex plugin list 2>&1 | tee /tmp/cx-list.txt
grep -q "kata-flight" /tmp/cx-list.txt && ok "kata-flight visible to codex" || bad "kata-flight not visible to codex"

section "Codex: plugin add kata-flight@kata-flight"
if codex plugin add kata-flight@kata-flight 2>&1; then ok "codex add"; else bad "codex add"; fi

section "RESULT"
if [ "$fail" -eq 0 ]; then echo "ALL INSTALL CHECKS PASSED"; else echo "SOME CHECKS FAILED (see [FAIL] above)"; fi
exit "$fail"
