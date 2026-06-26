#!/usr/bin/env sh
set -eu

usage() {
  cat <<'USAGE'
usage: flight-init.sh [--repo-root PATH] [--context-root PATH] [--rdr-home PATH] [--workspace]

Writes the Kata Flight seam:
  repo-local default: <repo>/.kata-flight/workspace
  workspace scope:    <workspace>/.kata-flight-workspace

The seam points at env/resources files in <repo>/.kata-flight/ by default.
If --rdr-home is omitted, init auto-binds a valid RDR engine at $WS/rdr or
$WS/process/rdr when exactly one exists. Use --rdr-home for non-standard paths.
USAGE
}

repo_root=""
context_root=""
rdr_home=""
rdr_home_source="explicit"
scope="repo"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      repo_root="${2:?missing --repo-root value}"
      shift 2
      ;;
    --context-root)
      context_root="${2:?missing --context-root value}"
      shift 2
      ;;
    --rdr-home)
      rdr_home="${2:?missing --rdr-home value}"
      shift 2
      ;;
    --workspace)
      scope="workspace"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$repo_root" ]; then
  repo_root="$(git rev-parse --show-toplevel)"
fi

repo_root="$(cd "$repo_root" && pwd -P)"
repo_name="$(basename "$repo_root")"
workspace_root="$(dirname "$repo_root")"

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
kata_flight_home="$(dirname "$script_dir")"

is_rdr_engine() {
  [ -d "$1/stages" ] && [ -d "$1/skills" ] && [ -d "$1/prompts" ] && [ -f "$1/TEMPLATE.md" ]
}

if [ -z "$rdr_home" ]; then
  rdr_home_source="auto"
  detected_rdr_home=""
  detected_rdr_count=0
  detected_rdr_list=""
  for candidate in "$workspace_root/rdr" "$workspace_root/process/rdr"; do
    if is_rdr_engine "$candidate"; then
      candidate="$(cd "$candidate" && pwd -P)"
      detected_rdr_home="$candidate"
      detected_rdr_count=$((detected_rdr_count + 1))
      detected_rdr_list="${detected_rdr_list}${detected_rdr_list:+ }$candidate"
    fi
  done

  if [ "$detected_rdr_count" -eq 1 ]; then
    rdr_home="$detected_rdr_home"
  elif [ "$detected_rdr_count" -gt 1 ]; then
    echo "stopped:ambiguous-rdr-home - found multiple canonical RDR engines: $detected_rdr_list" >&2
    echo "rerun with --rdr-home PATH" >&2
    exit 2
  fi
fi

parent_rdr_resources=""
inherited_context_root=""
if [ -f "$workspace_root/.rdr-workspace" ]; then
  parent_rdr_resources="$(
    WS="$workspace_root"
    RDR_RESOURCES=
    . "$workspace_root/.rdr-workspace" 2>/dev/null || true
    printf '%s' "${RDR_RESOURCES:-}"
  )"
  case "$parent_rdr_resources" in
    */context/rdr-resources.md)
      candidate_context_root="$(dirname "$(dirname "$parent_rdr_resources")")"
      if [ -f "$candidate_context_root/context/rdr-resources.md" ] &&
         [ -d "$candidate_context_root/rdr/evidence" ]; then
        inherited_context_root="$candidate_context_root"
      fi
      ;;
  esac
fi

if [ -z "$context_root" ]; then
  context_root="${inherited_context_root:-$repo_root}"
fi
context_root="$(cd "$context_root" && pwd -P)"

rdr_project_resources=""
if [ -n "$parent_rdr_resources" ]; then
  rdr_project_resources="$parent_rdr_resources"
  [ -f "$rdr_project_resources" ] || rdr_project_resources=""
fi
if [ -z "$rdr_project_resources" ] && [ -f "$context_root/context/rdr-resources.md" ]; then
  rdr_project_resources="$context_root/context/rdr-resources.md"
elif [ -z "$rdr_project_resources" ] && [ -f "$context_root/.rdr/resources.md" ]; then
  rdr_project_resources="$context_root/.rdr/resources.md"
fi

seam_dir="$repo_root/.kata-flight"
mkdir -p "$seam_dir"
printf '%s\n' "*" > "$seam_dir/.gitignore"

env_file="$seam_dir/env.md"
resources_file="$seam_dir/resources.md"
rdr_project_resources_ref="$rdr_project_resources"
if [ -n "$rdr_project_resources" ]; then
  rdr_resources_link="$seam_dir/rdr-resources.md"
  if ln -sfn "$rdr_project_resources" "$rdr_resources_link" 2>/dev/null; then
    rdr_project_resources_ref="$rdr_resources_link -> $rdr_project_resources"
  fi
fi

arc_corpora_status="not checked"
if command -v arc >/dev/null 2>&1; then
  arc_tmp="${TMPDIR:-/tmp}/kata-flight-arc-corpora-$$.json"
  if arc --json corpus list > "$arc_tmp" 2>/dev/null; then
    if command -v jq >/dev/null 2>&1; then
      arc_count="$(jq -r '(.data.corpora // []) | length' "$arc_tmp" 2>/dev/null || printf '?')"
      arc_corpora_status="available ($arc_count corpora reported by arc)"
    else
      arc_corpora_status="available (run arc corpus list; jq unavailable for count)"
    fi
  else
    arc_corpora_status="arc installed, but corpus list failed"
  fi
  rm -f "$arc_tmp"
else
  arc_corpora_status="arc not found on PATH"
fi

if [ "$scope" = "workspace" ]; then
  marker="$workspace_root/.kata-flight-workspace"
else
  marker="$seam_dir/workspace"
fi

cat > "$env_file" <<EOF
# Kata Flight path map

| Variable | Value |
| --- | --- |
| KATA_FLIGHT_HOME | $kata_flight_home |
| KATA_FLIGHT_CONSUMER_ROOT | $repo_root |
| KATA_FLIGHT_CONTEXT_ROOT | $context_root |
| KATA_FLIGHT_RESOURCES | $resources_file |
EOF

if [ -n "$rdr_home" ]; then
  rdr_home="$(cd "$rdr_home" && pwd -P)"
  if ! is_rdr_engine "$rdr_home"; then
    echo "stopped:rdr-home-not-engine - $rdr_home lacks stages/, skills/, prompts/, or TEMPLATE.md" >&2
    exit 2
  fi
  cat >> "$env_file" <<EOF
| KATA_FLIGHT_RDR_HOME | $rdr_home |
| KATA_FLIGHT_RDR_HOME_SOURCE | $rdr_home_source |
EOF
fi

cat > "$resources_file" <<'EOF'
# Kata Flight Resources

## Runtime

- `kata` CLI: required. Install and docs: <https://katatracker.com/>.
  Go install: `go install go.kenn.io/kata/cmd/kata@latest`.
- `roborev` CLI: required for review/refine/triage skills. Install and docs:
  <https://roborev.io/>. Shell install:
  `curl -fsSL https://roborev.io/install.sh | bash`; Go install:
  `go install go.kenn.io/roborev/cmd/roborev@latest`.
- RDR engine: optional; auto-bound from `$WS/rdr` or `$WS/process/rdr` when exactly one valid engine exists. Use `--rdr-home` for non-standard paths.

## Project Context

- Project guidelines: `context/project-guidelines.md` under `KATA_FLIGHT_CONTEXT_ROOT`, if present.
- RDR evidence: `rdr/evidence/` under `KATA_FLIGHT_CONTEXT_ROOT`, if the project uses RDR evidence.
EOF

if [ -n "$rdr_project_resources" ]; then
  {
    printf '\n%s\n\n' '## RDR Resources'
    printf '%s\n' "- Inherited project evidence index: \`$rdr_project_resources_ref\`."
  } >> "$resources_file"
else
  cat >> "$resources_file" <<'EOF'

## RDR Resources

No project RDR resources were found during init. If this repo uses RDR, add a
project evidence index under `KATA_FLIGHT_CONTEXT_ROOT/context/rdr-resources.md`
or initialize the parent RDR seam so `RDR_RESOURCES` points at the project
evidence index.
EOF
fi

cat >> "$resources_file" <<'EOF'

## Optional Research Corpora

Arcaneum corpora are useful for RDR/reference grounding, quotes, and prior art.
They are not runtime dependencies of Kata Flight. Before citing or quoting a hit,
open the source, verify the passage, and anchor the citation to the source title
plus DOI/arXiv/URL/page when available.
EOF

cat >> "$resources_file" <<EOF

Arcaneum status during init: $arc_corpora_status.

No corpora are selected by default. Before a kata review or RDR step relies on
Arcaneum, ask the user or deciding agent which corpora to include, using
\`arc corpus list\` as the source of available names and descriptions.

Follow-up: ask an LLM or the user to compare the project README with
\`arc corpus list\`, then update only this block with the selected corpora and
the reason each supports the current project.
EOF

{
  printf '%s\n' "# Kata Flight seam marker. Generated by kata-flight-init; edit deliberately."
  printf '%s\n' "# Source via nearest-wins resolver: repo .kata-flight/workspace, else workspace .kata-flight-workspace."
  printf '%s\n' "export KATA_FLIGHT_HOME='$kata_flight_home'"
  printf '%s\n' "export KATA_FLIGHT_CONSUMER_ROOT='$repo_root'"
  printf '%s\n' "export KATA_FLIGHT_EXPECTED_REPO_BASENAME='$repo_name'"
  printf '%s\n' "export KATA_FLIGHT_CONTEXT_ROOT='$context_root'"
  printf '%s\n' "export KATA_FLIGHT_ENV='$env_file'"
  printf '%s\n' "export KATA_FLIGHT_RESOURCES='$resources_file'"
  if [ -n "$rdr_home" ]; then
    printf '%s\n' "export KATA_FLIGHT_RDR_HOME='$rdr_home'"
    printf '%s\n' "export KATA_FLIGHT_RDR_HOME_SOURCE='$rdr_home_source'"
  fi
} > "$marker"

# Compatibility path for existing skill snippets. Keep it as a sourceable file.
{
  printf '%s\n' "# Compatibility shim. Prefer .kata-flight/workspace in new code."
  printf '%s\n' ". '$marker'"
} > "$seam_dir/env"

printf '%s\n' "wrote $marker"
printf '%s\n' "wrote $seam_dir/.gitignore"
printf '%s\n' "wrote $env_file"
printf '%s\n' "wrote $resources_file"
if [ -n "$rdr_home" ]; then
  printf '%s\n' "bound RDR home ($rdr_home_source): $rdr_home"
else
  printf '%s\n' "no RDR home auto-detected; use --rdr-home for non-standard locations"
fi
