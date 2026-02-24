#!/usr/bin/env bash
set -euo pipefail

# Verify and execute release bootstrap/start.sh using minisign.
# Convenience wrapper for the documented "Production-ish" flow.

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 2; }; }
need curl
need minisign

ORG="${ORG:-default82}"
REPO="${REPO:-RALF}"
VERSION="${VERSION:-}"
PUBKEY="${PUBKEY:-}"
PUBKEY_FILE="${PUBKEY_FILE:-}"
RUN_AFTER_VERIFY="${RUN_AFTER_VERIFY:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --pubkey) PUBKEY="${2:-}"; shift 2 ;;
    --pubkey-file) PUBKEY_FILE="${2:-}"; shift 2 ;;
    --verify-only) RUN_AFTER_VERIFY=0; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: verify-start.sh --version <tag> (--pubkey <key> | --pubkey-file <file>) [--verify-only]

Env:
  ORG, REPO, VERSION, PUBKEY, PUBKEY_FILE, RUN_AFTER_VERIFY=1|0
EOF
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$VERSION" ]] || { echo "VERSION is required"; exit 2; }

if [[ -z "$PUBKEY" ]]; then
  if [[ -n "$PUBKEY_FILE" ]]; then
    [[ -f "$PUBKEY_FILE" ]] || { echo "PUBKEY_FILE not found: $PUBKEY_FILE" >&2; exit 2; }
    PUBKEY="$(awk 'NF && $1 !~ /^untrusted/ {print; exit}' "$PUBKEY_FILE")"
  else
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    default_pub="${repo_root}/bootstrap/release/minisign.pub"
    if [[ -f "$default_pub" ]]; then
      PUBKEY="$(awk 'NF && $1 !~ /^untrusted/ {print; exit}' "$default_pub")"
      PUBKEY_FILE="$default_pub"
    fi
  fi
fi
[[ -n "$PUBKEY" ]] || { echo "PUBKEY is required (or provide --pubkey-file / bootstrap/release/minisign.pub)"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

base="https://github.com/${ORG}/${REPO}/releases/download/${VERSION}"
curl -fsSL "${base}/start.sh" -o "$tmp/start.sh"
curl -fsSL "${base}/start.sh.minisig" -o "$tmp/start.sh.minisig"
minisign -Vm "$tmp/start.sh" -P "$PUBKEY"

echo "[verify-start] verified: ${ORG}/${REPO} ${VERSION}"
if [[ "$RUN_AFTER_VERIFY" == "1" ]]; then
  exec bash "$tmp/start.sh"
fi
