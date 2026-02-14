#!/bin/bash
set -euo pipefail

##############################################################################
# Semaphore Setup Verification Script
#
# Prüft ob alle Voraussetzungen für Semaphore erfüllt sind
##############################################################################

echo "=========================================="
echo "Semaphore Setup Verification"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# Function für Checks
check_ok() {
  echo "✅ $1"
}

check_warn() {
  echo "⚠️  $1"
  WARNINGS=$((WARNINGS + 1))
}

check_fail() {
  echo "❌ $1"
  ERRORS=$((ERRORS + 1))
}

# 1. Semaphore Container Status
echo "=== Container Status ==="
if pct status 10015 2>/dev/null | grep -q "running"; then
  check_ok "Semaphore Container (10015) läuft"
else
  check_fail "Semaphore Container (10015) läuft NICHT"
fi

# 2. Semaphore Web-UI erreichbar
if curl -sf -m5 http://10.10.100.15:3000/api/ping > /dev/null 2>&1; then
  check_ok "Semaphore Web-UI erreichbar (http://10.10.100.15:3000)"
else
  check_fail "Semaphore Web-UI NICHT erreichbar"
fi

# 3. SSH-Keys
echo ""
echo "=== SSH Keys ==="
if [ -f /root/.ssh/semaphore/ralf-ansible ]; then
  check_ok "Private Key existiert (/root/.ssh/semaphore/ralf-ansible)"
else
  check_fail "Private Key fehlt"
fi

if [ -f /root/.ssh/semaphore/ralf-ansible.pub ]; then
  check_ok "Public Key existiert (/root/.ssh/semaphore/ralf-ansible.pub)"
else
  check_fail "Public Key fehlt"
fi

# 4. SSH-Zugriff zu Containern
echo ""
echo "=== SSH Connectivity ==="
CONTAINERS="2010:svc-postgres 2011:svc-mariadb 2012:svc-gitea 4030:web-netbox 4040:web-snipeit 10015:ops-semaphore"

SSH_SUCCESS=0
SSH_TOTAL=0

for entry in $CONTAINERS; do
  CTID=$(echo $entry | cut -d: -f1)
  HOST=$(echo $entry | cut -d: -f2)
  IP=$(pct exec $CTID -- hostname -I 2>/dev/null | awk '{print $1}')

  SSH_TOTAL=$((SSH_TOTAL + 1))

  # Gitea needs explicit port 22
  SSH_PORT=22
  if [ "$HOST" = "svc-gitea" ]; then
    SSH_PORT=22
  fi

  if ssh -i /root/.ssh/semaphore/ralf-ansible \
     -p $SSH_PORT \
     -o StrictHostKeyChecking=no \
     -o UserKnownHostsFile=/dev/null \
     -o ConnectTimeout=5 \
     root@$IP "hostname" &>/dev/null; then
    check_ok "SSH zu $HOST ($IP)"
    SSH_SUCCESS=$((SSH_SUCCESS + 1))
  else
    check_fail "SSH zu $HOST ($IP) fehlgeschlagen"
  fi
done

# 5. Gitea Repository
echo ""
echo "=== Git Repository ==="
if curl -sf -m5 http://10.10.20.12:3000/RALF-Homelab/ralf > /dev/null 2>&1; then
  check_ok "Gitea Repository erreichbar (http://10.10.20.12:3000/RALF-Homelab/ralf)"
else
  check_warn "Gitea Repository nicht erreichbar oder nicht öffentlich"
fi

# 6. Credentials
echo ""
echo "=== Credentials ==="
if [ -f /var/lib/ralf/credentials.env ]; then
  check_ok "credentials.env existiert"

  source /var/lib/ralf/credentials.env

  # Prüfe wichtige Credentials
  CREDS_OK=0
  CREDS_TOTAL=0

  for var in POSTGRES_MASTER_PASS MARIADB_ROOT_PASS GITEA_PG_PASS NETBOX_PG_PASS SNIPEIT_MYSQL_PASS SEMAPHORE_PG_PASS; do
    CREDS_TOTAL=$((CREDS_TOTAL + 1))
    if [ -n "${!var:-}" ]; then
      CREDS_OK=$((CREDS_OK + 1))
    fi
  done

  if [ $CREDS_OK -eq $CREDS_TOTAL ]; then
    check_ok "Alle wichtigen Credentials gesetzt ($CREDS_OK/$CREDS_TOTAL)"
  else
    check_warn "Einige Credentials fehlen ($CREDS_OK/$CREDS_TOTAL)"
  fi
else
  check_fail "credentials.env nicht gefunden"
fi

# 7. Ansible Collections
echo ""
echo "=== Ansible Setup ==="
if pct exec 10015 -- ansible-galaxy collection list 2>/dev/null | grep -q community.general; then
  check_ok "Ansible Collections installiert (community.general, community.postgresql, etc.)"
else
  check_warn "Ansible Collections möglicherweise nicht vollständig"
fi

# 8. Inventory
echo ""
echo "=== Inventory ==="
if [ -f /root/ralf/.worktrees/feature/ralf-completion/iac/ansible/inventory/hosts.yml ]; then
  check_ok "Ansible Inventory existiert"
else
  check_fail "Ansible Inventory fehlt"
fi

# 9. Test-Playbooks
echo ""
echo "=== Test-Playbooks ==="
if [ -f /root/ralf/.worktrees/feature/ralf-completion/iac/ansible/playbooks/test-connectivity.yml ]; then
  check_ok "Test-Connectivity Playbook vorhanden"
else
  check_warn "Test-Connectivity Playbook fehlt"
fi

if [ -f /root/ralf/.worktrees/feature/ralf-completion/iac/ansible/playbooks/test-environment.yml ]; then
  check_ok "Test-Environment Playbook vorhanden"
else
  check_warn "Test-Environment Playbook fehlt"
fi

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "✅ Erfolgreich: $((SSH_SUCCESS + CREDS_OK)) Checks"
echo "⚠️  Warnungen: $WARNINGS"
echo "❌ Fehler: $ERRORS"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  echo "🎉 Alle automatisierten Schritte abgeschlossen!"
  echo ""
  echo "Nächste Schritte (manuell in Semaphore Web-UI):"
  echo "1. SSH-Key zu Key Store hinzufügen"
  echo "2. Public Key zu Gitea hinzufügen"
  echo "3. Repository in Semaphore konfigurieren"
  echo "4. Environment Variables konfigurieren"
  echo ""
  echo "Dokumentation: docs/semaphore-*.md"
  exit 0
elif [ $ERRORS -eq 0 ]; then
  echo "✅ Grundlegende Voraussetzungen erfüllt"
  echo "⚠️  Einige optionale Komponenten fehlen (siehe Warnungen)"
  echo ""
  echo "Kann mit manuellen Schritten fortfahren."
  exit 0
else
  echo "❌ Kritische Fehler gefunden!"
  echo ""
  echo "Bitte Fehler beheben bevor fortgefahren wird."
  exit 1
fi
