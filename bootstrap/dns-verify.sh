#!/usr/bin/env bash
set -euo pipefail

log() { printf '[dns-verify] %s\n' "$*"; }
warn() { printf '[dns-verify][warn] %s\n' "$*" >&2; }
err() { printf '[dns-verify][error] %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE=""
RUNTIME_DIR_OVERRIDE=""
RESOLVER_OVERRIDE=""

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
    --resolver)
      RESOLVER_OVERRIDE="${2:-}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap/dns-verify.sh [--config FILE] [--runtime-dir DIR] [--resolver IP]

Verifies required RALF service FQDNs against the configured DNS resolver.
Writes results to: $RUNTIME_DIR/dns/dns-verify.jsonl
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

RALF_DOMAIN="${RALF_DOMAIN:-otta.zone}"
RUNTIME_DIR="${RUNTIME_DIR_OVERRIDE:-${RUNTIME_DIR:-/opt/ralf/runtime}}"
RESOLVER="${RESOLVER_OVERRIDE:-${RALF_DNS_RESOLVER:-10.10.0.1}}"

DNS_DIR="$RUNTIME_DIR/dns"
RESULTS_FILE="$DNS_DIR/dns-verify.jsonl"
mkdir -p "$DNS_DIR"
: > "$RESULTS_FILE"

records=(
  "postgresql 10.10.20.10"
  "minio 10.10.30.10"
  "gitea 10.10.40.10"
  "vaultwarden 10.10.50.10"
  "prometheus 10.10.80.10"
  "ki 10.10.90.10"
  "semaphore 10.10.100.10"
  "n8n 10.10.100.20"
  "matrix 10.10.110.10"
)

query_ip() {
  local fqdn="$1"
  local resolver="$2"

  if command -v dig >/dev/null 2>&1; then
    dig +short @"$resolver" "$fqdn" A | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print; exit}'
    return 0
  fi

  if command -v drill >/dev/null 2>&1; then
    drill @"$resolver" "$fqdn" A 2>/dev/null | awk '/\tA\t/ && $5 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $5; exit}'
    return 0
  fi

  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$fqdn" "$resolver" 2>/dev/null | awk '/^Address: / {v=$2; sub(/#.*/, "", v); if (v ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) print v}' | tail -n 1
    return 0
  fi

  warn "Kein Resolver-Tool (dig/drill/nslookup) verfuegbar, fallback auf getent (lokaler Resolver)."
  getent hosts "$fqdn" | awk 'NR==1 {print $1}'
}

PASS=0
FAIL=0

for entry in "${records[@]}"; do
  name="${entry%% *}"
  expected_ip="${entry##* }"
  fqdn="${name}.${RALF_DOMAIN}"

  actual_ip="$(query_ip "$fqdn" "$RESOLVER" || true)"
  status="Warnung"
  if [[ "$actual_ip" == "$expected_ip" ]]; then
    status="OK"
    PASS=$((PASS + 1))
    log "$fqdn -> $actual_ip (OK)"
  else
    FAIL=$((FAIL + 1))
    warn "$fqdn -> ${actual_ip:-<leer>} (erwartet: $expected_ip)"
  fi

  printf '{"ts":"%s","resolver":"%s","fqdn":"%s","expected_ip":"%s","actual_ip":"%s","status":"%s"}\n' \
    "$(date -Iseconds)" "$RESOLVER" "$fqdn" "$expected_ip" "${actual_ip:-}" "$status" >> "$RESULTS_FILE"
done

log "Ergebnis: $PASS OK, $FAIL Warnung(en)"
log "Detail: $RESULTS_FILE"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
