#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n==> $*"; }

# Cleanup Helper
destroy_if_exists() {
  local ctid=$1
  if pct status "$ctid" >/dev/null 2>&1; then
    log "Cleanup: Lösche CT $ctid"
    pct stop "$ctid" 2>/dev/null || true
    pct destroy "$ctid"
  fi
}

log "=== Full Bootstrap Integration Test ==="

# Optional: Cleanup (für Clean-Room-Test)
if [[ "${CLEAN_ROOM:-false}" == "true" ]]; then
  log "CLEAN_ROOM=true - Lösche existierende Container"
  destroy_if_exists 2010
  destroy_if_exists 2012
  destroy_if_exists 10015
fi

# Credentials laden
if [[ ! -f /var/lib/ralf/credentials.env ]]; then
  echo "ERROR: /var/lib/ralf/credentials.env nicht gefunden"
  echo "Erstelle Credentials mit: bash bootstrap/generate-credentials.sh"
  exit 1
fi

source /var/lib/ralf/credentials.env

# Bootstrap ausführen
log "Phase 1: PostgreSQL"
bash bootstrap/create-postgresql.sh

log "Phase 2: Gitea (mit Repository-Erstellung)"
bash bootstrap/create-gitea.sh

log "Phase 3: Semaphore (mit Auto-Configure)"
bash bootstrap/create-and-fill-runner.sh

# Verifications
log "=== Verifications ==="

# 1. PostgreSQL läuft
if pct exec 2010 -- systemctl is-active postgresql >/dev/null 2>&1; then
  echo "✅ PostgreSQL Service aktiv"
else
  echo "❌ PostgreSQL Service NICHT aktiv"
  exit 1
fi

# 2. Gitea läuft
if pct exec 2012 -- systemctl is-active gitea >/dev/null 2>&1; then
  echo "✅ Gitea Service aktiv"
else
  echo "❌ Gitea Service NICHT aktiv"
  exit 1
fi

# 3. Gitea Repository existiert
REPO_CHECK=$(curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf 2>/dev/null | jq -r '.name' 2>/dev/null || echo "")
if [[ "$REPO_CHECK" == "ralf" ]]; then
  echo "✅ Gitea Repository RALF-Homelab/ralf existiert"
else
  echo "❌ Gitea Repository existiert NICHT"
  exit 1
fi

# 4. Semaphore läuft
if pct exec 10015 -- systemctl is-active semaphore >/dev/null 2>&1; then
  echo "✅ Semaphore Service aktiv"
else
  echo "❌ Semaphore Service NICHT aktiv"
  exit 1
fi

# 5. Semaphore konfiguriert
if pct exec 10015 -- test -f /root/.semaphore-configured 2>/dev/null; then
  echo "✅ Semaphore wurde auto-konfiguriert"
else
  echo "⚠️  Semaphore wurde NICHT auto-konfiguriert"
  echo "    (möglicherweise AUTO_CONFIGURE=false gesetzt)"
fi

log "=== Test erfolgreich ==="
echo ""
echo "Alle Komponenten deployed und verifiziert"
echo ""
echo "Next Steps:"
echo "  1. Code pushen:"
echo "     cd /root/ralf"
echo "     git remote add gitea http://10.10.20.12:3000/RALF-Homelab/ralf.git"
echo "     git push gitea main"
echo ""
echo "  2. Semaphore UI: http://10.10.100.15:3000"
echo "  3. Gitea UI: http://10.10.20.12:3000"
