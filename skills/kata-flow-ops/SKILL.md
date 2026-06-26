---
name: kata-flow-ops
argument-hint: --dashboard | --reap [--days N]
description: 'Use for a read-only kata flow dashboard or stuck-state report. Shows lifecycle depth, inbox, batch depth, and illegal/stale states without mutating git or kata. Trigger for backlog status, stuck katas, or $kata-flow-ops.'
---

# kata-flow-ops

A read-only operator lens over the ship-flow state machine. The single-valued
`lifecycle:*` namespace (see the label-vocabulary reference) makes the whole flow's state
**queryable** and illegal states **greppable** — this skill renders both.

**Read-only, full stop.** Both modes only `kata list`/`kata labels` and report.
Neither mutates git or the tracker: the dashboard counts, the reaper **surfaces**
(it never `kata assign`/`label rm`/`close`). Acting on what it finds is a human
decision (see the per-row next-step in the ship-flow-state-machine reference).

## Usage

```
/kata-flow-ops --dashboard   # funnel depth: lifecycle:* counts + inbox + batch:* depth
/kata-flow-ops --reap        # surface illegal/stuck states (does NOT fix them)
/kata-flow-ops --reap --days N   # stale-reviewed threshold (default 7)
```

## CLI gotchas (read before trusting any count)

- **Read labels from `kata list --json .issues[].labels[]`** — they are **bare
  strings** there. Do **not** use `kata show --json .issue.labels`: it reports
  `null` even when labels exist (the ship-flow-state-machine reference §5.2). Every query
  below feeds off `kata list … --json`.
- `lifecycle:*` is **single-valued** — exactly one per kata is legal; zero or two
  is an illegal state the reaper catches.
- `owner != null` is the real "in-flight" signal; `lifecycle:resolving|refining|shipping`
  is the labelled twin. They must agree — disagreement is the orphaned/abandoned defect.

## `--dashboard` — the funnel depth (§4.2)

One snapshot of open work. Pull every open kata once, bucket by namespace.

```sh
kata list --status open --json > /tmp/kfo-open.json

# lifecycle:* depth (filed = open kata with NO lifecycle:* label)
jq -r '
  .issues
  | map(.labels // [])
  | (map(select(any(startswith("lifecycle:"))|not)) | length) as $filed
  | "filed     \($filed)",
    "queued    \([.[]|select(any(.=="lifecycle:queued"))]|length)",
    "reviewed  \([.[]|select(any(.=="lifecycle:reviewed"))]|length)",
    "resolving \([.[]|select(any(.=="lifecycle:resolving"))]|length)",
    "refining  \([.[]|select(any(.=="lifecycle:refining"))]|length)",
    "shipping  \([.[]|select(any(.=="lifecycle:shipping"))]|length)"
' /tmp/kfo-open.json

# human inbox: inbox:* ∪ kind:rdr-seed
jq -r '
  .issues | map(.labels // [])
  | "inbox:needs-review \([.[]|select(any(.=="inbox:needs-review"))]|length)",
    "inbox:hold         \([.[]|select(any(.=="inbox:hold"))]|length)",
    "kind:rdr-seed      \([.[]|select(any(.=="kind:rdr-seed"))]|length)"
' /tmp/kfo-open.json

# waiting on an in-flight RDR (not inbox): defect trackers, close when the RDR implements
jq -r '"kind:rdr-tracked   \([.issues[]|select((.labels//[])|any(.=="kind:rdr-tracked"))]|length)"' /tmp/kfo-open.json

# seed funnel depth (WIP-limit view): split rdr-seeds into DOMAIN vs TOOLING so
# the real domain-RDR pressure isn't inflated by kata/flow tooling seeds. A seed
# whose area:* names a tooling surface (flow/kata/process) is tooling; the rest
# are domain. A standing DOMAIN backlog is the stale-seed risk Stage-2 re-validate
# exists for — report the count so a deep funnel is visible, not silent.
jq -r '
  [.issues[] | select((.labels//[])|any(.=="kind:rdr-seed"))] as $seeds
  | ($seeds | map(select((.labels//[])|any(test("^area:(flow|kata|process|tooling)")))) | length) as $tool
  | "rdr-seed:tooling  \($tool)",
    "rdr-seed:domain   \(($seeds|length) - $tool)   (the real domain-RDR pressure)"
' /tmp/kfo-open.json

# per batch:* depth (one row per drainable group)
jq -r '
  [.issues[].labels[]? | select(startswith("batch:"))]
  | group_by(.) | map({k:.[0], n:length}) | sort_by(-.n)[]
  | "\(.k)  \(.n)"
' /tmp/kfo-open.json
```

Report the three blocks under headers `lifecycle:`, `inbox:`, `batch:`. `filed +
queued + reviewed + resolving + refining + shipping` should equal the open count
**minus** any kata carrying two `lifecycle:*` — a mismatch is itself a finding;
point the reader at `--reap`.

## `--reap` — the stuck-state sweep (§4.3)

Surface illegal states. **These are the exact §4 stuck-state queries** (each reads
`.issues[].labels`, bare strings). The reaper **lists short_ids and the rule each
tripped — it does not act**. Each row's remedy is a human move per
the ship-flow-state-machine reference "Next steps".

```sh
# orphaned claim: a SHIP LOCK (owner kata-ship/*) with no phase label —
# a crashed/abandoned ship. A human-held kata (owner is a person, e.g. a
# manual `kata assign`) is NOT orphaned — exempt non-kata-ship/* owners so the
# reaper doesn't nag work a person is deliberately holding. (Shake-out finding.)
kata list --status open --json | jq -r '.issues[]|select((.owner // "" | startswith("kata-ship/")) and ((.labels//[])|any(test("^lifecycle:(resolving|refining|shipping)$"))|not))|.short_id'

# abandoned mid-ship: phase label but no owner (lock vanished mid-flight)
kata list --status open --json | jq -r '.issues[]|select(.owner==null and ((.labels//[])|any(test("^lifecycle:(resolving|refining|shipping)$"))))|.short_id'

# illegal: two lifecycle:* at once (a non-atomic rm+add transition crashed)
kata list --status open --json | jq -r '.issues[]|select((.labels//[]|map(select(startswith("lifecycle:")))|length)>1)|.short_id'

# stale: lifecycle:reviewed older than N days, never shipped (default N=7)
kata list --status open --label lifecycle:reviewed --json | jq -r --argjson days 7 '
  (now - ($days*86400)) as $cut
  | .issues[] | select(((.updated_at // .created_at) | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) < $cut) | .short_id'

# stale seed: kind:rdr-seed idle longer than the seed threshold (default 14 days,
# 2x reviewed) — a seed that sits between Seed and Propose long enough for its
# references/scope to go stale (the exact gap Stage-2 "re-validate the seed"
# covers). Surface it so the funnel stays a WIP-limited queue, not a roach motel.
kata list --status open --label kind:rdr-seed --json | jq -r --argjson days 14 '
  (now - ($days*86400)) as $cut
  | .issues[] | select(((.updated_at // .created_at) | sub("\\.[0-9]+Z$";"Z") | fromdateiso8601) < $cut) | .short_id'

# tracker drift: for each kind:rdr-tracked kata, read its `tracks: cli/NNNN`
# comment (kata show --json .comments[].body — comments DO return on show,
# unlike labels) and the named RDR's `**Status**:` line. Surface: Implemented
# (close overdue — Stage 8's close step was missed), Demoted/Abandoned/
# Superseded (defect lost its RDR → kata-scope-review), or no tracks: line
# (mislabeled). Draft/Final = healthy in-flight, stays quiet.
kata list --status open --label kind:rdr-tracked --json | jq -r '.issues[].short_id'
```

Report one section per rule: the rule name, the short_ids, and the canonical
human remedy (re-stamp lifecycle / reclaim or release the lock / drop the extra
label / re-ship or close the stale review / re-validate or close the stale seed).
A clean sweep reports "no stuck states." Surface only; never mutate.

> Notes: `lifecycle:reviewed` carries no timestamp in its label (labels can't hold
> a value — the label-vocabulary reference); the stale query uses the kata's `updated_at`
> as the staleness proxy. If a date-bearing `reviewed-at:` comment exists it is the
> truer signal, but the comment read is optional and stays read-only.

## Failure modes

| Condition | Action |
|---|---|
| `kata list` fails / not configured | Refuse; surface (cannot read the tracker). |
| `kata show` tempting for labels | Don't — use `kata list --json .issues[].labels` (the §5.2 `labels:null` gotcha). |
| A query returns rows | List them; **never** auto-fix. The reaper surfaces; a human acts. |
| Counts don't reconcile to the open total | Report it as a finding and point at `--reap` (likely a double `lifecycle:*`). |

## See also

- the ship-flow state machine reference **§4.2** (dashboard) and **§4.3**
  (reaper + the verbatim stuck-state queries) — the design rationale; **§5.2** for
  the kata-CLI gotchas these queries are written around.
- the consumer label vocabulary reference — the namespace model: `lifecycle:*`
  single-valued, `inbox:*`/`kind:rdr-seed` as the human inbox, `batch:*` ephemeral.
- `/kata-flight` — the primary drain; this skill is its natural read-only preflight.
