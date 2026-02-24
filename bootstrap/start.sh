#!/usr/bin/env bash
set -euo pipefail

# Thin launcher for GitHub one-liner bootstrap.
# Fetches the repo (git clone if available, else tarball) and delegates to `ralf bootstrap`.

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 2; }; }
log() { printf '[start] %s\n' "$*"; }

need bash
need curl

ORG="${ORG:-default82}"
REPO="${REPO:-RALF}"
REF="${RALF_REF:-main}"
REPO_URL="${RALF_REPO_URL:-https://github.com/${ORG}/${REPO}.git}"

ref_kind="auto"
if [[ "$REF" =~ ^[0-9a-fA-F]{40}$ ]]; then
  ref_kind="commit"
elif [[ "$REF" =~ ^v?[0-9]+(\.[0-9]+)*([.-][A-Za-z0-9._-]+)?$ ]]; then
  ref_kind="tag"
else
  ref_kind="branch"
fi

default_tarball_url() {
  case "$ref_kind" in
    branch) printf 'https://github.com/%s/%s/archive/refs/heads/%s.tar.gz' "$ORG" "$REPO" "$REF" ;;
    tag) printf 'https://github.com/%s/%s/archive/refs/tags/%s.tar.gz' "$ORG" "$REPO" "$REF" ;;
    commit|auto) printf 'https://github.com/%s/%s/archive/%s.tar.gz' "$ORG" "$REPO" "$REF" ;;
  esac
}
TARBALL_URL="${RALF_TARBALL_URL:-$(default_tarball_url)}"

if [[ -z "${PROVISIONER:-}" ]]; then
  if command -v pct >/dev/null 2>&1; then
    PROVISIONER="proxmox_pct"
  elif command -v lxc >/dev/null 2>&1; then
    PROVISIONER="lxd"
  else
    PROVISIONER="host"
  fi
fi
export PROVISIONER

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

work="$tmp/repo"
mkdir -p "$work"

if command -v git >/dev/null 2>&1; then
  log "Fetching repository via git (${REPO_URL} @ ${REF})"
  git init -q "$work"
  git -C "$work" remote add origin "$REPO_URL"
  if git -C "$work" fetch --depth 1 origin "$REF" >/dev/null 2>&1; then
    git -C "$work" checkout -q FETCH_HEAD
  elif git -C "$work" fetch --depth 1 origin "refs/heads/${REF}" >/dev/null 2>&1; then
    git -C "$work" checkout -q FETCH_HEAD
  else
    echo "failed to fetch repository ref: ${REF}" >&2
    exit 2
  fi
else
  need tar
  log "Fetching repository via tarball (${TARBALL_URL}; ref_kind=${ref_kind})"
  curl -fsSL "$TARBALL_URL" -o "$tmp/repo.tar.gz"
  mkdir -p "$tmp/extract"
  tar -xzf "$tmp/repo.tar.gz" -C "$tmp/extract"
  src_dir="$(find "$tmp/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [[ -n "$src_dir" ]] || { echo "failed to extract repository tarball" >&2; exit 2; }
  cp -a "$src_dir"/. "$work"/
fi

[[ -x "$work/bin/ralf" ]] || chmod +x "$work/bin/ralf" 2>/dev/null || true
[[ -x "$work/ralf" ]] || chmod +x "$work/ralf" 2>/dev/null || true
[[ -x "$work/ralf" ]] || { echo "missing executable bootstrap engine: ralf" >&2; exit 2; }

args=()
[[ "${TUI:-0}" == "1" ]] && args+=(--tui)
[[ "${NON_INTERACTIVE:-0}" == "1" ]] && args+=(--non-interactive)
[[ "${YES:-0}" == "1" ]] && args+=(--yes)
[[ "${FORCE:-0}" == "1" ]] && args+=(--force)
[[ -n "${PROFILE:-}" ]] && args+=(--profile "$PROFILE")
[[ -n "${NETWORK_CIDR:-}" ]] && args+=(--network-cidr "$NETWORK_CIDR")
[[ -n "${BASE_DOMAIN:-}" ]] && args+=(--base-domain "$BASE_DOMAIN")
[[ -n "${CT_HOSTNAME:-}" ]] && args+=(--ct-hostname "$CT_HOSTNAME")
[[ -n "${ANSWERS_FILE:-}" ]] && args+=(--answers-file "$ANSWERS_FILE")
[[ -n "${EXPORT_ANSWERS:-}" ]] && args+=(--export-answers "$EXPORT_ANSWERS")

if [[ "${APPLY:-0}" == "1" || "${AUTO_APPLY:-0}" == "1" ]]; then
  args+=(--apply)
fi

cd "$work"
log "Delegating to ./ralf bootstrap --provisioner ${PROVISIONER}"
exec ./ralf bootstrap --provisioner "$PROVISIONER" "${args[@]}"
