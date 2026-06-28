#!/usr/bin/env bash
# Offline tests for scripts/kata-q.sh. Feeds captured + synthetic fixtures via
# KATA_Q_FIXTURE so the helpers never invoke `kata` — no daemon, no auth needed.
# Mirrors test/install/run.sh's section/ok/bad harness.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIX="$HERE/fixtures"
# shellcheck source=../../scripts/kata-q.sh
. "$HERE/../../scripts/kata-q.sh"

fail=0
ok()  { printf '  [PASS] %s\n' "$1"; }
bad() { printf '  [FAIL] %s -- got: %s\n' "$1" "${2:-}"; fail=1; }
section() { printf '\n========== %s ==========\n' "$1"; }
# eq EXPECTED ACTUAL LABEL
eq() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "$2"; fi; }

section "kq_ready_ids: ready items have no labels — exclusion is native"
got=$(KATA_Q_FIXTURE="$FIX/ready.json" kq_ready_ids | tr '\n' ' ' | sed 's/ $//')
want=$(jq -r '.issues[].short_id' "$FIX/ready.json" | tr '\n' ' ' | sed 's/ $//')
eq "$want" "$got" "ready ids match fixture short_ids"

section "kq_open_ids_by_label: iterate .issues[], never .[]"
got=$(KATA_Q_FIXTURE="$FIX/list-cost.json" kq_open_ids_by_label cost | wc -l | tr -d ' ')
want=$(jq -r '.issues | length' "$FIX/list-cost.json")
eq "$want" "$got" "open-by-label count matches .issues length"

section "kq_show_brief: status/owner/labels for one issue (unowned)"
got=$(KATA_Q_FIXTURE="$FIX/show.json" kq_show_brief z7xb)
case "$got" in
  *"status=open"*"owner=-"*"labels=cost,kata-json,tooling"*) ok "brief renders unowned owner as -" ;;
  *) bad "brief renders unowned owner as -" "$got" ;;
esac

section "kq_owner: null-safe — unowned returns empty, not an error"
got=$(KATA_Q_FIXTURE="$FIX/show.json" kq_owner z7xb); rc=$?
eq "0" "$rc" "kq_owner exits 0 on unowned (no jq error)"
eq "" "$got" "kq_owner empty on unowned"
got=$(KATA_Q_FIXTURE="$FIX/show-owned.json" kq_owner z7xb)
eq "kata-ship/abc123" "$got" "kq_owner returns owner when owned"

section "kq_owned_by: the defect fix — never throws on unowned"
KATA_Q_FIXTURE="$FIX/show.json" kq_owned_by z7xb "kata-ship/"; rc=$?
eq "1" "$rc" "unowned issue -> clean exit 1 (NOT jq error 5)"
KATA_Q_FIXTURE="$FIX/show-owned.json" kq_owned_by z7xb "kata-ship/"; rc=$?
eq "0" "$rc" "owned-by-kata-ship -> exit 0"
KATA_Q_FIXTURE="$FIX/show-owned.json" kq_owned_by z7xb "kata-flight/"; rc=$?
eq "1" "$rc" "owned by other prefix -> exit 1"

section "kq_blockers / kq_links: top-level .links, not .issue.related"
got=$(KATA_Q_FIXTURE="$FIX/show.json" kq_blockers z7xb)
eq "" "$got" "no blocks edges -> empty (related links ignored)"
got=$(KATA_Q_FIXTURE="$FIX/show-blocked.json" kq_blockers z7xb)
eq "aa11" "$got" "synthetic blocks edge -> blocker short_id"
got=$(KATA_Q_FIXTURE="$FIX/show.json" kq_links z7xb | wc -l | tr -d ' ')
eq "2" "$got" "two related links surfaced"

section "kq_label_count: from kata labels --json"
got=$(KATA_Q_FIXTURE="$FIX/labels.json" kq_label_count cost)
want=$(jq -r '.labels[] | select(.label=="cost").count' "$FIX/labels.json")
eq "$want" "$got" "cost label count matches fixture"
got=$(KATA_Q_FIXTURE="$FIX/labels.json" kq_label_count no-such-label-xyz)
eq "0" "$got" "absent label -> 0, not empty"

section "canary: .issue.labels is null — helpers must not read it"
got=$(jq -r '.issue.labels' "$FIX/show.json")
eq "null" "$got" "fixture confirms .issue.labels is null (use top-level .labels)"

if [ "$fail" -eq 0 ]; then
  printf '\nALL CHECKS PASSED\n'; exit 0
else
  printf '\nSOME CHECKS FAILED\n'; exit 1
fi
