#!/usr/bin/env bash
set -euo pipefail

log() { printf '[start] %s\n' "$*"; }
warn() { printf '[start][warn] %s\n' "$*" >&2; }
err() { printf '[start][error] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

NON_INTERACTIVE=0
APPLY=0
YES=0
CONFIG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=1; shift ;;
    --apply) APPLY=1; shift ;;
    --yes) YES=1; shift ;;
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap/start.sh [--apply] [--yes] [--non-interactive] [--config FILE]

Default mode is plan (no changes). Use --apply for real execution.
EOF
      exit 0
      ;;
    *)
      err "Unbekannte Option: $1"
      exit 2
      ;;
  esac
done

if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$REPO_ROOT/bootstrap/bootstrap.env"
fi

prompt() {
  local key="$1" prompt_text="$2" default_value="$3"
  local value=""
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    printf '%s' "$default_value"
    return
  fi
  if [[ -t 0 ]]; then
    read -r -p "$prompt_text [$default_value]: " value || true
    printf '%s' "${value:-$default_value}"
  else
    printf '%s' "$default_value"
  fi
}

prompt_secret() {
  local prompt_text="$1"
  local value=""
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    printf ''
    return
  fi
  if [[ -t 0 ]]; then
    read -r -s -p "$prompt_text: " value || true
    printf '\n' >&2
    printf '%s' "$value"
  else
    printf ''
  fi
}

PROXMOX_HOST="$(prompt PROXMOX_HOST 'Proxmox Host/IP' '10.10.10.10')"
PROXMOX_NODE="$(prompt PROXMOX_NODE 'Proxmox Node Name' 'pve-deploy')"
PROXMOX_API_ENDPOINT="$(prompt PROXMOX_API_ENDPOINT 'Proxmox API Endpoint' "https://${PROXMOX_HOST}:8006/api2/json")"
RALF_DOMAIN="$(prompt RALF_DOMAIN 'Primäre Domain' 'otta.zone')"
RALF_NETWORK_CIDR="$(prompt RALF_NETWORK_CIDR 'RALF Netzwerk-CIDR' '10.10.0.0/16')"
RUNTIME_DIR="$(prompt RUNTIME_DIR 'Runtime-Verzeichnis' '/opt/ralf/runtime')"

PROXMOX_API_TOKEN_ID="${PROXMOX_API_TOKEN_ID:-}"
PROXMOX_API_TOKEN_SECRET="${PROXMOX_API_TOKEN_SECRET:-}"

if [[ "$APPLY" == "1" ]]; then
  if [[ -z "$PROXMOX_API_TOKEN_ID" ]]; then
    PROXMOX_API_TOKEN_ID="$(prompt_secret 'Proxmox API Token ID (nur bei Apply nötig)')"
  fi
  if [[ -z "$PROXMOX_API_TOKEN_SECRET" ]]; then
    PROXMOX_API_TOKEN_SECRET="$(prompt_secret 'Proxmox API Token Secret (nur bei Apply nötig)')"
  fi
fi

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR" || true

cat > "$CONFIG_FILE" <<EOF
PROXMOX_HOST="$PROXMOX_HOST"
PROXMOX_NODE="$PROXMOX_NODE"
PROXMOX_API_ENDPOINT="$PROXMOX_API_ENDPOINT"
RALF_DOMAIN="$RALF_DOMAIN"
RALF_NETWORK_CIDR="$RALF_NETWORK_CIDR"
RALF_GATEWAY="10.10.0.1"
RALF_BRIDGE="vmbr0"
RALF_STORAGE="local-lvm"
RALF_TEMPLATE_STORAGE="local"
RALF_TEMPLATE_NAME="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
RALF_SSH_PUBKEY_FILE="/root/.ssh/ralf_ed25519.pub"
RUNTIME_DIR="$RUNTIME_DIR"
PROXMOX_API_TOKEN_ID="$PROXMOX_API_TOKEN_ID"
PROXMOX_API_TOKEN_SECRET="$PROXMOX_API_TOKEN_SECRET"
EOF
chmod 600 "$CONFIG_FILE" || true

MODE="plan"
[[ "$APPLY" == "1" ]] && MODE="apply"

log "Konfiguration geschrieben: $CONFIG_FILE"
log "Modus: $MODE"
log "Host: $PROXMOX_HOST | Node: $PROXMOX_NODE | Netzwerk: $RALF_NETWORK_CIDR"

if [[ "$APPLY" == "1" && "$YES" != "1" && "$NON_INTERACTIVE" != "1" && -t 0 ]]; then
  answer="$(prompt CONFIRM 'Mit APPLY fortfahren? (yes/no)' 'no')"
  if [[ "$answer" != "yes" ]]; then
    warn "Abbruch durch Benutzer."
    exit 1
  fi
fi

cmd=("$REPO_ROOT/bootstrap/bootrunner.sh" "--config" "$CONFIG_FILE")
[[ "$APPLY" == "1" ]] && cmd+=("--apply")
[[ "$YES" == "1" ]] && cmd+=("--yes")

exec "${cmd[@]}"
