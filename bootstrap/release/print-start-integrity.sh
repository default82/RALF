#!/usr/bin/env bash
set -euo pipefail

# Print commit/SHA256 information for bootstrap/start.sh to support
# the pinned-commit "Danger Zone" bootstrap flow.

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 2; }; }
need git
need sha256sum

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
commit="${COMMIT:-HEAD}"
json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit) commit="${2:-}"; shift 2 ;;
    --json) json=1; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: print-start-integrity.sh [--commit <ref>] [--json]

Prints commit + SHA256 for bootstrap/start.sh.
Uses `git show <ref>:bootstrap/start.sh | sha256sum` for deterministic output.
EOF
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

full_commit="$(git -C "$repo_root" rev-parse "$commit")"
sha="$(git -C "$repo_root" show "${full_commit}:bootstrap/start.sh" | sha256sum | awk '{print $1}')"

if [[ "$json" == "1" ]]; then
  cat <<EOF
{
  "commit": "${full_commit}",
  "file": "bootstrap/start.sh",
  "sha256": "${sha}"
}
EOF
else
  echo "COMMIT=${full_commit}"
  echo "FILE=bootstrap/start.sh"
  echo "SHA256=${sha}"
fi
