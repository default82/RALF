#!/bin/bash
set -euo pipefail

##############################################################################
# Semaphore Environment Variables Export
#
# Zeigt alle Environment Variables an, die in Semaphore konfiguriert werden
# müssen, mit ihren aktuellen Werten aus credentials.env
##############################################################################

# Lade Credentials
if [ ! -f /var/lib/ralf/credentials.env ]; then
  echo "FEHLER: /var/lib/ralf/credentials.env nicht gefunden!"
  exit 1
fi

source /var/lib/ralf/credentials.env

echo "=========================================="
echo "Semaphore Environment Variables"
echo "=========================================="
echo ""
echo "Kopiere diese Variables in Semaphore:"
echo "Project → Environment → + New Environment Variable"
echo ""

# Function um Variable auszugeben
print_var() {
  local var_name="$1"
  local var_value="${!var_name:-NOT_SET}"
  local is_secret="${2:-yes}"

  if [ "$var_value" = "NOT_SET" ]; then
    echo "⚠️  $var_name = NOT_SET"
  else
    if [ "$is_secret" = "yes" ]; then
      echo "🔐 $var_name = ${var_value:0:8}... (Secret: ✅)"
    else
      echo "📝 $var_name = $var_value (Secret: ❌)"
    fi
  fi
}

echo "=== PostgreSQL (CT 2010) ==="
print_var "POSTGRES_MASTER_PASS"
echo ""

echo "=== MariaDB (CT 2011) ==="
print_var "MARIADB_ROOT_PASS"
echo ""

echo "=== Gitea (CT 2012) ==="
print_var "GITEA_PG_PASS"
print_var "GITEA_ADMIN1_USER" "no"
print_var "GITEA_ADMIN1_EMAIL" "no"
print_var "GITEA_ADMIN1_PASS"
echo ""

echo "=== NetBox (CT 4030) ==="
print_var "NETBOX_PG_PASS"
print_var "NETBOX_SECRET_KEY"
print_var "NETBOX_SUPERUSER_PASS"
echo ""

echo "=== Snipe-IT (CT 4040) ==="
print_var "SNIPEIT_MYSQL_PASS"
print_var "SNIPEIT_APP_KEY"
print_var "SNIPEIT_ADMIN_USER" "no"
print_var "SNIPEIT_ADMIN_EMAIL" "no"
print_var "SNIPEIT_ADMIN_PASS"
echo ""

echo "=== Vaultwarden (CT 2013) ==="
print_var "VAULTWARDEN_ADMIN_TOKEN"
print_var "VAULTWARDEN_PG_PASS"
echo ""

echo "=== Semaphore (CT 10015) ==="
print_var "SEMAPHORE_PG_PASS"
print_var "SEMAPHORE_ADMIN1_USER" "no"
print_var "SEMAPHORE_ADMIN1_EMAIL" "no"
print_var "SEMAPHORE_ADMIN1_PASS"
print_var "SEMAPHORE_ADMIN2_USER" "no"
print_var "SEMAPHORE_ADMIN2_EMAIL" "no"
print_var "SEMAPHORE_ADMIN2_PASS"
echo ""

echo "=========================================="
echo "Gesamt: $(grep -c "^export" /var/lib/ralf/credentials.env) Variables in credentials.env"
echo "=========================================="
echo ""
echo "📋 Vollständige Values anzeigen:"
echo "   source /var/lib/ralf/credentials.env && env | grep -E 'GITEA|NETBOX|SNIPEIT|POSTGRES|MARIADB|VAULTWARDEN|SEMAPHORE' | sort"
echo ""
echo "📝 In Semaphore eintragen:"
echo "   1. Login: http://10.10.100.15:3000"
echo "   2. Project → RALF Infrastructure → Environment"
echo "   3. Für jede Variable: + New Environment Variable"
echo "   4. Name eingeben, Value eingeben, Secret ✅ für Passwords"
echo ""
