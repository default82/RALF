#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# OPNsense Caddy Plugin API Inspector
# Zeigt verfügbare API-Endpunkte und aktuelle Konfiguration
##############################################################################

### CONFIG ###
OPNSENSE_HOST="${OPNSENSE_HOST:-10.10.0.1}"
OPNSENSE_PORT="${OPNSENSE_PORT:-8443}"
OPNSENSE_API_KEY="${OPNSENSE_API_KEY:-YOUR_API_KEY_HERE}"
OPNSENSE_API_SECRET="${OPNSENSE_API_SECRET:-YOUR_API_SECRET_HERE}"

BASE_URL="https://${OPNSENSE_HOST}:${OPNSENSE_PORT}/api"

### HELPER FUNCTIONS ###
log() { echo -e "\n==> $*"; }

api_call() {
  local method="$1"
  local endpoint="$2"

  curl -s -k -X "$method" \
    -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
    "${BASE_URL}${endpoint}"
}

### VALIDIERUNG ###
if [[ "$OPNSENSE_API_KEY" == "YOUR_API_KEY_HERE" ]]; then
  echo "ERROR: Bitte OPNSENSE_API_KEY setzen!"
  echo ""
  echo "API-Key erstellen:"
  echo "  1. OPNsense öffnen: https://${OPNSENSE_HOST}:${OPNSENSE_PORT}"
  echo "  2. System → Access → Users"
  echo "  3. User editieren → API Keys → Create API Key"
  echo ""
  echo "Dann ausführen:"
  echo "  export OPNSENSE_API_KEY='your-key'"
  echo "  export OPNSENSE_API_SECRET='your-secret'"
  echo "  bash $0"
  exit 1
fi

### API INSPECTION ###
log "Prüfe Caddy Service Status"
api_call GET "/caddy/service/status" | jq

log "Liste alle Reverse Proxy Domains"
api_call GET "/caddy/reverse_proxy/get" | jq

log "Liste alle Reverse Proxy Handler"
api_call GET "/caddy/reverse_proxy/searchHandler" | jq

log "Caddy General Settings"
api_call GET "/caddy/general/get" | jq

log "Verfügbare Caddy API Endpoints (Meta)"
echo "Standard OPNsense Caddy API Pattern:"
echo ""
echo "GET/POST   /api/caddy/service/status           - Service-Status"
echo "POST       /api/caddy/service/start            - Service starten"
echo "POST       /api/caddy/service/stop             - Service stoppen"
echo "POST       /api/caddy/service/restart          - Service neustarten"
echo "POST       /api/caddy/service/reconfigure      - Config neu laden"
echo ""
echo "GET        /api/caddy/reverse_proxy/get        - Domains auflisten"
echo "GET        /api/caddy/reverse_proxy/getDomain/{uuid} - Domain Details"
echo "POST       /api/caddy/reverse_proxy/addDomain  - Domain hinzufügen"
echo "POST       /api/caddy/reverse_proxy/setDomain/{uuid} - Domain ändern"
echo "POST       /api/caddy/reverse_proxy/delDomain/{uuid} - Domain löschen"
echo ""
echo "GET        /api/caddy/reverse_proxy/searchHandler - Handler auflisten"
echo "GET        /api/caddy/reverse_proxy/getHandler/{uuid} - Handler Details"
echo "POST       /api/caddy/reverse_proxy/addHandler - Handler hinzufügen"
echo "POST       /api/caddy/reverse_proxy/setHandler/{uuid} - Handler ändern"
echo "POST       /api/caddy/reverse_proxy/delHandler/{uuid} - Handler löschen"
echo ""
echo "GET        /api/caddy/general/get              - General Settings"
echo "POST       /api/caddy/general/set              - General Settings ändern"

log "HINWEIS"
echo "Falls obige Calls fehlschlagen (404), prüfe:"
echo "  • Ist os-caddy Plugin installiert?"
echo "    System → Firmware → Plugins → os-caddy"
echo "  • API-Permissions des Users korrekt?"
echo "  • Andere mögliche Endpunkte:"
echo "    /api/Caddy/... (mit Großbuchstaben)"
echo "    /api/caddyservice/... (alternative Benennung)"
