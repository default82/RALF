#!/usr/bin/env bash
set -euo pipefail

# Create release artifacts for bootstrap/start.sh:
# - start.sh
# - start.sh.minisig
# Optional:
# - start.sh.sha256
#
# Requirements:
# - minisign
# - git

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 2; }; }
need minisign
need git

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="${repo_root}/bootstrap/start.sh"
[[ -f "$src" ]] || { echo "missing file: $src" >&2; exit 2; }

OUT_DIR="${OUT_DIR:-${repo_root}/dist/bootstrap-release}"
MINISIGN_SECRET_KEY="${MINISIGN_SECRET_KEY:-}"
WITH_SHA256="${WITH_SHA256:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --secret-key) MINISIGN_SECRET_KEY="${2:-}"; shift 2 ;;
    --no-sha256) WITH_SHA256=0; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: sign-start.sh [--out-dir DIR] [--secret-key PATH] [--no-sha256]

Env:
  OUT_DIR
  MINISIGN_SECRET_KEY
  WITH_SHA256=1|0
EOF
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$MINISIGN_SECRET_KEY" ]] || {
  echo "MINISIGN_SECRET_KEY is required (path to minisign secret key)" >&2
  exit 2
}
[[ -f "$MINISIGN_SECRET_KEY" ]] || { echo "missing minisign secret key: $MINISIGN_SECRET_KEY" >&2; exit 2; }

mkdir -p "$OUT_DIR"

cp "$src" "$OUT_DIR/start.sh"
minisign -S -s "$MINISIGN_SECRET_KEY" -m "$OUT_DIR/start.sh" -x "$OUT_DIR/start.sh.minisig"

if [[ "$WITH_SHA256" == "1" ]]; then
  sha256sum "$OUT_DIR/start.sh" > "$OUT_DIR/start.sh.sha256"
fi

cat > "$OUT_DIR/manifest.txt" <<EOF
source_file=bootstrap/start.sh
git_commit=$(git -C "$repo_root" rev-parse HEAD)
created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
artifacts=start.sh,start.sh.minisig$([[ "$WITH_SHA256" == "1" ]] && printf ',start.sh.sha256')
EOF

echo "[sign-start] wrote artifacts to $OUT_DIR"
ls -1 "$OUT_DIR"
