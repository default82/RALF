#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Caddy Timeout Debugging für OPNsense
# Bitte auf OPNsense ausführen: ssh root@10.10.0.1 'bash -s' < caddy-debug-opnsense.sh
##############################################################################

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Caddy Timeout Debugging                                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

### 1. Caddy Status ###
echo "==> 1. Caddy Service Status"
if command -v caddy >/dev/null 2>&1; then
  echo "Caddy installed: $(caddy version)"
else
  echo "❌ Caddy nicht gefunden! Ist os-caddy Plugin installiert?"
fi

if command -v service >/dev/null 2>&1; then
  service caddy status || echo "❌ Caddy läuft nicht"
else
  systemctl status caddy --no-pager || echo "❌ Caddy läuft nicht"
fi
echo ""

### 2. Caddy Config Location ###
echo "==> 2. Caddy Konfiguration"
CADDY_CONFIG="/usr/local/etc/caddy/Caddyfile"
if [[ -f "$CADDY_CONFIG" ]]; then
  echo "Config gefunden: $CADDY_CONFIG"
  echo "Größe: $(wc -l < "$CADDY_CONFIG") Zeilen"
  echo ""
  echo "Inhalt:"
  cat "$CADDY_CONFIG"
else
  echo "❌ Caddyfile nicht gefunden an $CADDY_CONFIG"
  echo "Suche nach alternativen Pfaden..."
  find /usr/local /etc -name "Caddyfile" 2>/dev/null || echo "Keine Caddyfile gefunden"
fi
echo ""

### 3. Caddy Logs ###
echo "==> 3. Caddy Error Logs (letzte 50 Zeilen)"
if [[ -f "/var/log/caddy/error.log" ]]; then
  tail -50 /var/log/caddy/error.log
elif [[ -f "/var/log/caddy.log" ]]; then
  tail -50 /var/log/caddy.log
else
  echo "Logs nicht gefunden. Prüfe journalctl:"
  journalctl -u caddy -n 50 --no-pager 2>/dev/null || echo "Keine Logs verfügbar"
fi
echo ""

### 4. Listening Ports ###
echo "==> 4. Caddy Listening Ports"
netstat -an | grep -E ':(80|443|8443)\s' || sockstat -46l | grep caddy || echo "Keine Ports gefunden"
echo ""

### 5. Backend Connectivity von OPNsense ###
echo "==> 5. Backend Connectivity Tests von OPNsense"
echo ""
echo "Testing Gitea (10.10.20.12:3000):"
timeout 5 curl -s -o /dev/null -w "HTTP %{http_code} - Time: %{time_total}s\n" http://10.10.20.12:3000 2>&1 || echo "❌ TIMEOUT"

echo ""
echo "Testing Semaphore (10.10.100.15:3000):"
timeout 5 curl -s -o /dev/null -w "HTTP %{http_code} - Time: %{time_total}s\n" http://10.10.100.15:3000 2>&1 || echo "❌ TIMEOUT"

echo ""
echo "Testing Dashy (10.10.40.11:4000):"
timeout 5 curl -s -o /dev/null -w "HTTP %{http_code} - Time: %{time_total}s\n" http://10.10.40.11:4000 2>&1 || echo "❌ TIMEOUT"
echo ""

### 6. Firewall Rules ###
echo "==> 6. Firewall Rules (LAN → Backends)"
pfctl -sr | grep -E '(10\.10\.(20|40|100)|pass)' | head -20 || echo "Keine relevanten Rules gefunden"
echo ""

### 7. DNS Resolution ###
echo "==> 7. DNS Resolution Tests"
for host in gitea.otta.zone semaphore.otta.zone dashy.otta.zone; do
  echo "Resolving $host:"
  host "$host" 2>/dev/null || nslookup "$host" 2>/dev/null || echo "❌ DNS Fehler"
done
echo ""

### 8. Caddy Config Validation ###
echo "==> 8. Caddy Config Syntax Check"
if command -v caddy >/dev/null 2>&1; then
  if [[ -f "$CADDY_CONFIG" ]]; then
    caddy validate --config "$CADDY_CONFIG" 2>&1 || echo "❌ Config hat Syntax-Fehler"
  else
    echo "Keine Caddyfile zum Validieren"
  fi
fi
echo ""

### 9. Reverse Proxy Test ###
echo "==> 9. Caddy Reverse Proxy Test (lokal)"
echo "Testing http://localhost:80 mit Host-Header:"
curl -s -o /dev/null -w "HTTP %{http_code}\n" -H "Host: gitea.otta.zone" http://localhost:80 2>&1 || echo "❌ Caddy antwortet nicht"
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Diagnose abgeschlossen                                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Mögliche Ursachen für Timeouts:"
echo "  1. Caddy läuft nicht → service caddy start"
echo "  2. Falsche Backend-URLs (https:// statt http://)"
echo "  3. TLS Verification enabled für HTTP-Backends"
echo "  4. Firewall blockiert LAN → Backend Traffic"
echo "  5. DNS Resolution schlägt fehl"
echo "  6. Timeout-Werte zu niedrig gesetzt"
echo ""
echo "Quick Fix - Caddy neu starten:"
echo "  service caddy restart"
