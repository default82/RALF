#!/usr/bin/env bash
set -euo pipefail

log() { printf '[dns-opnsense-apply] %s\n' "$*"; }
warn() { printf '[dns-opnsense-apply][warn] %s\n' "$*" >&2; }
err() { printf '[dns-opnsense-apply][error] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE=""
RUNTIME_DIR_OVERRIDE=""
APPLY=0
YES=0
NON_INTERACTIVE=0
NO_VERIFY=0

OPNSENSE_HOST_OVERRIDE=""
OPNSENSE_USER_OVERRIDE=""
OPNSENSE_PORT_OVERRIDE=""
SSH_KEY_FILE_OVERRIDE=""
REMOTE_DIR_OVERRIDE=""
UNBOUND_TARGET_OVERRIDE=""
RESTART_CMD_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG_FILE="${2:-}"
      shift 2
      ;;
    --runtime-dir)
      RUNTIME_DIR_OVERRIDE="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    --yes)
      YES=1
      shift
      ;;
    --non-interactive)
      NON_INTERACTIVE=1
      shift
      ;;
    --no-verify)
      NO_VERIFY=1
      shift
      ;;
    --opnsense-host)
      OPNSENSE_HOST_OVERRIDE="${2:-}"
      shift 2
      ;;
    --opnsense-user)
      OPNSENSE_USER_OVERRIDE="${2:-}"
      shift 2
      ;;
    --opnsense-port)
      OPNSENSE_PORT_OVERRIDE="${2:-}"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY_FILE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR_OVERRIDE="${2:-}"
      shift 2
      ;;
    --unbound-target)
      UNBOUND_TARGET_OVERRIDE="${2:-}"
      shift 2
      ;;
    --restart-cmd)
      RESTART_CMD_OVERRIDE="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap/dns-opnsense-apply.sh [options]

Automates DNS rollout to OPNsense Unbound via SSH.

Default mode is PLAN (no remote changes).
Use --apply for remote deployment.

Options:
  --config FILE            Config file (default: bootstrap/bootstrap.env)
  --runtime-dir DIR        Override runtime directory
  --apply                  Execute remote deployment
  --yes                    Skip confirmation prompt in apply mode
  --non-interactive        Disable prompts
  --no-verify              Skip post-apply resolver verification
  --opnsense-host HOST     OPNsense host/IP override
  --opnsense-user USER     SSH user override (default: root)
  --opnsense-port PORT     SSH port override (default: 22)
  --ssh-key FILE           SSH private key override
  --remote-dir DIR         Remote staging directory override
  --unbound-target FILE    Remote target include file override
  --restart-cmd CMD        Remote restart command override
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

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

RUNTIME_DIR="${RUNTIME_DIR_OVERRIDE:-${RUNTIME_DIR:-/opt/ralf/runtime}}"
OPNSENSE_HOST="${OPNSENSE_HOST_OVERRIDE:-${RALF_DNS_OPNSENSE_HOST:-}}"
OPNSENSE_USER="${OPNSENSE_USER_OVERRIDE:-${RALF_DNS_OPNSENSE_USER:-root}}"
OPNSENSE_PORT="${OPNSENSE_PORT_OVERRIDE:-${RALF_DNS_OPNSENSE_PORT:-22}}"
SSH_KEY_FILE="${SSH_KEY_FILE_OVERRIDE:-${RALF_DNS_OPNSENSE_SSH_KEY_FILE:-}}"
REMOTE_DIR="${REMOTE_DIR_OVERRIDE:-${RALF_DNS_OPNSENSE_REMOTE_DIR:-/tmp/ralf-dns}}"
UNBOUND_TARGET="${UNBOUND_TARGET_OVERRIDE:-${RALF_DNS_OPNSENSE_UNBOUND_TARGET:-/usr/local/etc/unbound.opnsense.d/ralf.conf}}"
RESTART_CMD="${RESTART_CMD_OVERRIDE:-${RALF_DNS_OPNSENSE_RESTART_CMD:-configctl unbound restart}}"

if [[ -z "$OPNSENSE_HOST" ]]; then
  err "OPNsense Host fehlt. Setze RALF_DNS_OPNSENSE_HOST in der Config oder nutze --opnsense-host."
  exit 2
fi

if [[ -n "$SSH_KEY_FILE" && ! -f "$SSH_KEY_FILE" ]]; then
  err "SSH-Key-Datei nicht gefunden: $SSH_KEY_FILE"
  exit 2
fi

mkdir -p "$RUNTIME_DIR/dns"

log "Erzeuge DNS-Artefakte..."
bash "$REPO_ROOT/bootstrap/dns-unbound-opnsense.sh" --config "$CONFIG_FILE" --runtime-dir "$RUNTIME_DIR"

UNBOUND_LOCAL="$RUNTIME_DIR/dns/unbound-custom-options.conf"
CSV_LOCAL="$RUNTIME_DIR/dns/unbound-host-overrides.csv"

[[ -f "$UNBOUND_LOCAL" ]] || { err "Fehlendes Artefakt: $UNBOUND_LOCAL"; exit 1; }
[[ -f "$CSV_LOCAL" ]] || { err "Fehlendes Artefakt: $CSV_LOCAL"; exit 1; }

SSH_OPTS=(-p "$OPNSENSE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
SCP_OPTS=(-P "$OPNSENSE_PORT" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
if [[ -n "$SSH_KEY_FILE" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY_FILE")
  SCP_OPTS+=(-i "$SSH_KEY_FILE")
fi

REMOTE="$OPNSENSE_USER@$OPNSENSE_HOST"

if [[ "$APPLY" != "1" ]]; then
  log "PLAN: wuerde Artefakte nach $REMOTE:$REMOTE_DIR hochladen."
  log "PLAN: wuerde Unbound-Config nach $UNBOUND_TARGET deployen."
  log "PLAN: wuerde Restart ausfuehren: $RESTART_CMD"
  log "PLAN: Ausfuehren mit --apply (optional --yes)."
  exit 0
fi

if [[ "$YES" != "1" && "$NON_INTERACTIVE" != "1" && -t 0 ]]; then
  read -r -p "[dns-opnsense-apply] APPLY gegen $REMOTE ausfuehren? (yes/no): " answer || true
  if [[ "$answer" != "yes" ]]; then
    warn "Abbruch durch Benutzer."
    exit 1
  fi
fi

log "Staging-Verzeichnis auf OPNsense vorbereiten: $REMOTE_DIR"
ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$REMOTE_DIR'"

log "Artefakte hochladen"
scp "${SCP_OPTS[@]}" "$UNBOUND_LOCAL" "$CSV_LOCAL" "$REMOTE:$REMOTE_DIR/"

printf -v REMOTE_CMD "REMOTE_DIR=%q UNBOUND_TARGET=%q RESTART_CMD=%q bash -s" "$REMOTE_DIR" "$UNBOUND_TARGET" "$RESTART_CMD"

log "Unbound-Config deployen und neu laden"
ssh "${SSH_OPTS[@]}" "$REMOTE" "$REMOTE_CMD" <<'EOF'
set -euo pipefail

if [[ ! -f "$REMOTE_DIR/unbound-custom-options.conf" ]]; then
  echo "[remote][error] Missing staged file: $REMOTE_DIR/unbound-custom-options.conf" >&2
  exit 1
fi

install -d "$(dirname "$UNBOUND_TARGET")"
install -m 0644 "$REMOTE_DIR/unbound-custom-options.conf" "$UNBOUND_TARGET"

if command -v configctl >/dev/null 2>&1; then
  configctl unbound check >/dev/null 2>&1 || true
fi

sh -lc "$RESTART_CMD"
EOF

log "Remote-Deploy abgeschlossen: $UNBOUND_TARGET"

if [[ "$NO_VERIFY" == "1" ]]; then
  warn "Resolver-Verifikation wurde uebersprungen (--no-verify)."
  exit 0
fi

log "Starte Resolver-Verifikation gegen ${RALF_DNS_RESOLVER:-10.10.0.1}"
if bash "$REPO_ROOT/bootstrap/dns-verify.sh" --config "$CONFIG_FILE" --runtime-dir "$RUNTIME_DIR" --resolver "${RALF_DNS_RESOLVER:-10.10.0.1}"; then
  log "DNS-Verifikation erfolgreich."
else
  err "DNS-Verifikation fehlgeschlagen. Details: $RUNTIME_DIR/dns/dns-verify.jsonl"
  exit 1
fi
