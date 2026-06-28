#!/usr/bin/env sh
# kata-q.sh — canonical kata JSON query helpers for Kata Flight skills.
#
# Source this file, then call the functions. Every helper emits compact,
# agent-readable lines suitable for phase briefs. Helpers encode the three
# real kata JSON shapes so skills stop rediscovering them and retrying jq:
#
#   kata list  --json  ->  {kata_api_version, issues:[ {short_id,status,labels:[STR],owner?,...} ]}
#   kata ready --json  ->  {kata_api_version, issues:[ {short_id,...} ]}   # NO labels field
#   kata show  --json  ->  {issue:{owner|null, labels:null, ...}, labels:[{label}], links:[...], comments:[...]}
#   kata labels --json ->  {kata_api_version, labels:[{label,count}]}
#
# NEVER `jq '.[]'` over `kata list --json` (it is an object, not an array).
# NEVER read `.issue.labels` on show (always null) — use top-level `.labels[].label`.
# `owner` is ABSENT on unowned list/ready items and null on show — always read it
# null-safe (`.owner // ""`), or `startswith()` throws on unowned issues.
#
# Offline testing: set KATA_Q_FIXTURE=/path/to.json and the helpers read that
# file instead of invoking `kata`. The fixture must match the shape the helper
# expects (list/ready/show/labels). See test/kata-json/.

# _kq_list SHAPE ARGS... — run `kata <verb> --json` or read the fixture.
# SHAPE is the kata subcommand (list|ready|show|labels); ARGS are passed through.
_kq() {
  if [ -n "${KATA_Q_FIXTURE:-}" ]; then
    cat "$KATA_Q_FIXTURE"
  else
    kata "$@" --json
  fi
}

# list open short_ids carrying a label. Native --label does the filtering.
# usage: kq_open_ids_by_label <label>
kq_open_ids_by_label() {
  _kq list --status open --label "$1" | jq -r '.issues[].short_id'
}

# list ready short_ids for a label, excluding the never-flight set. The
# exclusion is NATIVE (--no-label); ready items carry no labels to jq-filter.
# usage: kq_ready_ids [label]
kq_ready_ids() {
  if [ -n "${1:-}" ]; then set -- --label "$1"; else set --; fi
  _kq ready "$@" \
    --no-label kind:rdr-seed --no-label inbox:hold --no-label umbrella \
    | jq -r '.issues[].short_id'
}

# compact status/labels/owner/priority for one issue (null-safe owner).
# usage: kq_show_brief <id>
kq_show_brief() {
  _kq show "$1" | jq -r '
    "status=\(.issue.status) priority=\(.issue.priority) "
    + "owner=\(.issue.owner // "-") "
    + "labels=\([.labels[].label] | join(","))"'
}

# null-safe owner string for one issue ("" when unowned). usage: kq_owner <id>
kq_owner() {
  _kq show "$1" | jq -r '.issue.owner // ""'
}

# true (exit 0) iff the issue is owned by a session matching PREFIX.
# Null-safe: a clean "not owned" returns exit 1, never a jq error.
# usage: kq_owned_by <id> <prefix>   e.g. kq_owned_by nnv8 "kata-ship/"
kq_owned_by() {
  _kq show "$1" | jq -e --arg p "$2" '(.issue.owner // "") | startswith($p)' >/dev/null
}

# top-level links for an issue, one per line: "<type> <from>-><to>".
# usage: kq_links <id>
kq_links() {
  _kq show "$1" | jq -r '.links[] | "\(.type) \(.from.qualified_id)->\(.to.qualified_id)"'
}

# short_ids that BLOCK the given issue (incoming blocks edges).
# usage: kq_blockers <id>
kq_blockers() {
  _kq show "$1" \
    | jq -r --arg id "$1" '.links[] | select(.type=="blocks" and .to.short_id==$id) | .from.short_id'
}

# count of issues carrying a label. usage: kq_label_count <label>
kq_label_count() {
  _kq labels | jq -r --arg l "$1" '(.labels[] | select(.label==$l) | .count) // 0'
}
