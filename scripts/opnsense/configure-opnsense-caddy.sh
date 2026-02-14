#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# OPNsense Caddy Plugin API Konfiguration für RALF Services
# Domain: otta.zone
##############################################################################

### CONFIG ###
OPNSENSE_HOST="${OPNSENSE_HOST:-10.10.0.1}"
OPNSENSE_PORT="${OPNSENSE_PORT:-8443}"
OPNSENSE_API_KEY="${OPNSENSE_API_KEY:-YOUR_API_KEY_HERE}"
OPNSENSE_API_SECRET="${OPNSENSE_API_SECRET:-YOUR_API_SECRET_HERE}"

BASE_URL="https://${OPNSENSE_HOST}:${OPNSENSE_PORT}/api/caddy"

### HELPER FUNCTIONS ###
log() { echo -e "\n==> $*"; }

api_call() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local url="${BASE_URL}${endpoint}"

  if [[ -n "$data" ]]; then
    curl -s -k -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$url"
  else
    curl -s -k -X "$method" \
      -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      "$url"
  fi
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

### DOMAINS ERSTELLEN ###
log "Erstelle Reverse Proxy Domains"

# Domain: gitea.otta.zone
log "Domain: gitea.otta.zone"
api_call POST "/reverse_proxy/domain" '{
  "domain": {
    "enabled": "1",
    "domain": "gitea.otta.zone",
    "port": "443",
    "description": "Gitea Git Repository"
  }
}' | jq

# Domain: semaphore.otta.zone
log "Domain: semaphore.otta.zone"
api_call POST "/reverse_proxy/domain" '{
  "domain": {
    "enabled": "1",
    "domain": "semaphore.otta.zone",
    "port": "443",
    "description": "Semaphore CI/CD"
  }
}' | jq

# Domain: dashy.otta.zone
log "Domain: dashy.otta.zone"
api_call POST "/reverse_proxy/domain" '{
  "domain": {
    "enabled": "1",
    "domain": "dashy.otta.zone",
    "port": "443",
    "description": "Dashy Dashboard"
  }
}' | jq

# Domain: vault.otta.zone
log "Domain: vault.otta.zone"
api_call POST "/reverse_proxy/domain" '{
  "domain": {
    "enabled": "1",
    "domain": "vault.otta.zone",
    "port": "443",
    "description": "Vaultwarden Password Manager"
  }
}' | jq

### HANDLERS ERSTELLEN ###
log "Erstelle Reverse Proxy Handlers"

# Handler: gitea
log "Handler: gitea → 10.10.20.12:3000"
api_call POST "/reverse_proxy/handler" '{
  "handler": {
    "enabled": "1",
    "description": "Gitea Backend",
    "domain": "gitea.otta.zone",
    "upstream_protocol": "http",
    "upstream_host": "10.10.20.12",
    "upstream_port": "3000"
  }
}' | jq

# Handler: semaphore
log "Handler: semaphore → 10.10.100.15:3000"
api_call POST "/reverse_proxy/handler" '{
  "handler": {
    "enabled": "1",
    "description": "Semaphore Backend",
    "domain": "semaphore.otta.zone",
    "upstream_protocol": "http",
    "upstream_host": "10.10.100.15",
    "upstream_port": "3000"
  }
}' | jq

# Handler: dashy
log "Handler: dashy → 10.10.40.11:4000"
api_call POST "/reverse_proxy/handler" '{
  "handler": {
    "enabled": "1",
    "description": "Dashy Backend",
    "domain": "dashy.otta.zone",
    "upstream_protocol": "http",
    "upstream_host": "10.10.40.11",
    "upstream_port": "4000"
  }
}' | jq

# Handler: vaultwarden
log "Handler: vaultwarden → 10.10.30.10:8080"
api_call POST "/reverse_proxy/handler" '{
  "handler": {
    "enabled": "1",
    "description": "Vaultwarden Backend",
    "domain": "vault.otta.zone",
    "upstream_protocol": "http",
    "upstream_host": "10.10.30.10",
    "upstream_port": "8080"
  }
}' | jq

### APPLY CHANGES ###
log "Wende Konfiguration an"
api_call POST "/service/reconfigure" | jq

log "FERTIG ✅"
echo ""
echo "Konfigurierte Domains:"
echo "  • https://gitea.otta.zone"
echo "  • https://semaphore.otta.zone"
echo "  • https://dashy.otta.zone"
echo "  • https://vault.otta.zone"
echo ""
echo "Nächste Schritte:"
echo "  1. DNS A-Records für *.otta.zone anlegen"
echo "  2. Ports 80/443 in Firewall freigeben (WAN)"
echo "  3. Let's Encrypt Zertifikate werden automatisch erstellt"
