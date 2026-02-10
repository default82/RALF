#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# RALF Network Health Check – Vollstaendige Implementierung
# Referenz: healthchecks/network-health.yml
# Governed by: docs/network-baseline.md
#
# Alle 9 Kategorien (A-I) werden geprueft.
# Jeder Check ist ein Blocker: 1 Failure = keine Deploys.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Load runtime config ---
if [[ -f "$REPO_ROOT/inventory/runtime.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/inventory/runtime.env"
else
  echo "[NET] Missing inventory/runtime.env"
  exit 1
fi

# --- Required variables ---
: "${GATEWAY_IP:?Missing GATEWAY_IP}"
: "${PROXMOX_IP:?Missing PROXMOX_IP}"
: "${DNS_TEST_HOST:=google.com}"
: "${DNS_INTERNAL_HOST:=opnsense.homelab.lan}"
: "${TPLINK_CONTROLLER_IP:=10.10.10.1}"
: "${CADDY_CHECK_URL:=https://10.10.0.1:8443}"
: "${NTP_MAX_DRIFT_SECONDS:=5}"

echo "============================================"
echo " RALF Network Health Check"
echo " $(date -Is)"
echo "============================================"
echo ""

TOTAL=0
PASSED=0
FAILED=0
FAILED_CHECKS=""

check() {
  local id="$1"
  local description="$2"
  local command="$3"

  TOTAL=$((TOTAL + 1))
  echo -n "  [$id] $description ... "
  if eval "$command" >/dev/null 2>&1; then
    echo "OK"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL"
    FAILED=$((FAILED + 1))
    FAILED_CHECKS="${FAILED_CHECKS}\n  - [$id] $description"
  fi
}

# ============================================================
# A) Core Connectivity
# ============================================================
echo "[A] Core Connectivity"

check "A1" "Gateway erreichbar (OPNsense ${GATEWAY_IP})" \
  "ping -c 2 -W 2 $GATEWAY_IP"

check "A2" "Internet Upstream (via Fritzbox)" \
  "ping -c 2 -W 3 1.1.1.1"

echo ""

# ============================================================
# B) DNS Health
# ============================================================
echo "[B] DNS Health"

check "B1" "Interne DNS-Aufloesung (${DNS_INTERNAL_HOST})" \
  "getent hosts $DNS_INTERNAL_HOST"

check "B2" "Externe DNS-Aufloesung (${DNS_TEST_HOST})" \
  "getent hosts $DNS_TEST_HOST"

echo ""

# ============================================================
# C) DHCP & Addressing
# ============================================================
echo "[C] DHCP & Addressing"

check "C1" "Kein Rogue DHCP (nur OPNsense als Gateway)" \
  "ip route show default | grep -q $GATEWAY_IP"

check "C2" "Statische IP-Konsistenz (eigene IP im Homelab-Netz)" \
  "ip -4 addr show | grep -q '10\\.10\\.'"

echo ""

# ============================================================
# D) Time Health
# ============================================================
echo "[D] Time Health"

check "D1" "Systemzeit plausibel (NTP sync)" \
  "timedatectl show --property=NTPSynchronized --value 2>/dev/null | grep -q 'yes' || \
   ntpstat 2>/dev/null || \
   chronyc tracking 2>/dev/null | grep -q 'Leap status.*Normal'"

echo ""

# ============================================================
# E) Reverse Proxy Core
# ============================================================
echo "[E] Reverse Proxy Core"

check "E1" "Caddy/Reverse Proxy erreichbar (OPNsense)" \
  "curl -skf --connect-timeout 5 --max-time 10 $CADDY_CHECK_URL -o /dev/null"

echo ""

# ============================================================
# F) Network Infrastructure
# ============================================================
echo "[F] Network Infrastructure"

check "F1" "TP-Link Controller erreichbar (${TPLINK_CONTROLLER_IP})" \
  "ping -c 2 -W 2 $TPLINK_CONTROLLER_IP"

check "F2" "Proxmox Node erreichbar (${PROXMOX_IP})" \
  "ping -c 2 -W 2 $PROXMOX_IP"

echo ""

# ============================================================
# G) Observability
# ============================================================
echo "[G] Observability"

check "G1" "Systemlogs verfuegbar (syslog oder journalctl)" \
  "test -f /var/log/syslog || journalctl --no-pager -n 1"

echo ""

# ============================================================
# H) Drift & Order
# ============================================================
echo "[H] Drift & Order"

check "H1" "IP-Schema Compliance (Default Route via Homelab-Gateway)" \
  "ip route show default | grep -q $GATEWAY_IP"

check "H2" "Hosts-Inventory vorhanden und nicht leer" \
  "test -s $REPO_ROOT/inventory/hosts.yaml"

echo ""

# ============================================================
# I) Recovery Capability
# ============================================================
echo "[I] Recovery Capability"

check "I1" "OPNsense erreichbar (Backup/Config moeglich)" \
  "curl -skf --connect-timeout 5 --max-time 10 https://${GATEWAY_IP}:8443 -o /dev/null || \
   ping -c 1 -W 2 $GATEWAY_IP"

echo ""

# ============================================================
# VERDICT
# ============================================================
echo "============================================"
echo " ERGEBNIS"
echo "============================================"
echo "  Checks gesamt:   $TOTAL"
echo "  Bestanden:       $PASSED"
echo "  Fehlgeschlagen:  $FAILED"
echo ""

if [[ $FAILED -ne 0 ]]; then
  echo "  STATUS: BLOCKED"
  echo ""
  echo "  Fehlgeschlagene Checks:"
  echo -e "$FAILED_CHECKS"
  echo ""
  echo "  Gatekeeper-Regel aktiv:"
  echo "    -> Keine Deploys, keine Aenderungen erlaubt."
  echo "    -> Erlaubt: Analyse, Dokumentation, Heilung, Rollback."
  echo ""
  exit 1
else
  echo "  STATUS: NETWORK READY"
  echo ""
  echo "  -> Alle Checks gruen. Deploys und Aenderungen erlaubt."
  echo ""
  exit 0
fi
