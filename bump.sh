#!/usr/bin/env bash
#
# bump.sh - bump the kata-flight plugin version across both manifests, then
# commit, tag, and push.
#
# The version field is duplicated in two manifests that loaders read directly:
#   .claude-plugin/plugin.json   (Claude Code marketplace)
#   .codex-plugin/plugin.json    (Codex marketplace)
# This script is the only sanctioned way to change them, which keeps them in sync.
#
# Usage:
#   ./bump.sh patch          # 0.0.0 -> 0.0.1
#   ./bump.sh minor          # 0.0.0 -> 0.1.0
#   ./bump.sh major          # 0.0.0 -> 1.0.0
#   ./bump.sh 1.4.2          # set an explicit version
#   ./bump.sh patch --dry-run    # show what would change, touch nothing
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS=(
  "$ROOT/.claude-plugin/plugin.json"
  "$ROOT/.codex-plugin/plugin.json"
)

die() { echo "bump: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: ./bump.sh <patch|minor|major|X.Y.Z> [--dry-run]"

ARG="$1"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

for f in "${MANIFESTS[@]}"; do
  [[ -f "$f" ]] || die "missing manifest: $f"
done

read_version() {
  python3 - "$1" <<'PY'
import json, sys
with open(sys.argv[1]) as fh:
    print(json.load(fh)["version"])
PY
}

CURRENT="$(read_version "${MANIFESTS[0]}")"
for f in "${MANIFESTS[@]:1}"; do
  other="$(read_version "$f")"
  [[ "$other" == "$CURRENT" ]] || die "manifests out of sync: ${MANIFESTS[0]}=$CURRENT, $f=$other (fix by hand before bumping)"
done

if [[ "$ARG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  NEXT="$ARG"
else
  IFS='.' read -r MA MI PA <<<"$CURRENT"
  case "$ARG" in
    major) NEXT="$((MA + 1)).0.0" ;;
    minor) NEXT="${MA}.$((MI + 1)).0" ;;
    patch) NEXT="${MA}.${MI}.$((PA + 1))" ;;
    *) die "unknown bump kind '$ARG' (expected patch|minor|major|X.Y.Z)" ;;
  esac
fi

[[ "$NEXT" != "$CURRENT" ]] || die "version is already $NEXT"

TAG="v$NEXT"
echo "bump: $CURRENT -> $NEXT"
for f in "${MANIFESTS[@]}"; do
  echo "  - ${f#"$ROOT"/}"
done

if [[ "$DRY_RUN" == 1 ]]; then
  echo "  (dry run - no files changed, no commit, no tag, no push)"
  exit 0
fi

[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || die "working tree is dirty - commit or stash first"
if git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists"
fi

for f in "${MANIFESTS[@]}"; do
  python3 - "$f" "$NEXT" <<'PY'
import json, sys
path, new = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)
data["version"] = new
with open(path, "w") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
done

git -C "$ROOT" add "${MANIFESTS[@]}"
git -C "$ROOT" commit -m "chore(release): $TAG"
git -C "$ROOT" tag -a "$TAG" -m "kata-flight $TAG"
git -C "$ROOT" push origin HEAD
git -C "$ROOT" push origin "$TAG"

echo "bump: released $TAG (commit + tag pushed to origin)"
