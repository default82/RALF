#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n==> $*"; }

log "=== Regression Test: Bootstrap Re-Run (Idempotenz) ==="

# Credentials laden
if [[ ! -f /var/lib/ralf/credentials.env ]]; then
  echo "ERROR: /var/lib/ralf/credentials.env nicht gefunden"
  exit 1
fi

source /var/lib/ralf/credentials.env

# Alle Scripts 2x ausführen
SCRIPTS=(
  "bootstrap/create-postgresql.sh"
  "bootstrap/create-gitea.sh"
  "bootstrap/create-and-fill-runner.sh"
)

FAILED=0

for script in "${SCRIPTS[@]}"; do
  log "Testing: $script (Run 1)"
  if bash "$script"; then
    echo "✅ Run 1 erfolgreich"
  else
    echo "❌ Run 1 fehlgeschlagen"
    FAILED=1
    continue
  fi

  log "Testing: $script (Run 2 - Idempotenz-Check)"
  if bash "$script"; then
    echo "✅ Run 2 erfolgreich (idempotent)"
  else
    echo "❌ Run 2 fehlgeschlagen"
    FAILED=1
    continue
  fi

  echo "✅ $script ist idempotent"
done

if [[ $FAILED -eq 0 ]]; then
  log "=== Alle Scripts sind idempotent ==="
  exit 0
else
  log "=== Fehler: Einige Scripts sind NICHT idempotent ==="
  exit 1
fi
