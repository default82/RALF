#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Dashy Status Check Fix
#
# Problem: Client-seitige Status-Checks funktionieren nicht von extern
# Lösung: 3 Optionen zur Auswahl
##############################################################################

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Dashy Status Check Fix                                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Wähle eine Lösung:"
echo ""
echo "1. Status-Checks DEAKTIVIEREN (schnell)"
echo "   → Keine Status-Badges mehr"
echo "   → Alle Services sind einfach nur Links"
echo ""
echo "2. Nur INTERNE URLs (funktioniert nur im Netzwerk)"
echo "   → Status-Checks funktionieren nur wenn User im 10.10.0.0/16 ist"
echo "   → Optimal mit VPN"
echo ""
echo "3. EXTERNE URLs via Caddy (nach Caddy-Fix)"
echo "   → Nutzt otta.zone URLs"
echo "   → Funktioniert von überall"
echo "   → Erfordert funktionierende Caddy-Config"
echo ""
read -p "Wahl (1/2/3): " CHOICE

CTID=4001
CONFIG_PATH="/opt/dashy/user-data/conf.yml"

case $CHOICE in
  1)
    echo ""
    echo "==> Deaktiviere Status-Checks"
    pct exec "$CTID" -- bash -c "cat > $CONFIG_PATH" <<'EOFCONFIG'
---
pageInfo:
  title: RALF Homelab Dashboard
  description: Self-orchestrating homelab infrastructure platform
  logo: https://i.ibb.co/qWWpD0v/astro-dab-128.png
  navLinks:
    - title: RALF GitHub
      path: https://github.com/default82/RALF
    - title: Gitea (Lokal)
      path: http://10.10.20.12:3000

appConfig:
  theme: nord-frost
  layout: auto
  iconSize: medium
  language: de
  statusCheck: false
  disableUpdateChecks: true
  hideComponents:
    - footer

sections:
  - name: P1 - Core Infrastructure
    icon: fas fa-server
    displayData:
      cols: 3
      collapsed: false
    items:
      - title: PostgreSQL
        description: Zentrale Datenbank (CT 2010)
        icon: hl-postgresql
        url: http://10.10.20.10:5432

      - title: Semaphore
        description: CI/CD Orchestration (CT 10015)
        icon: hl-semaphore
        url: http://10.10.100.15:3000

      - title: Gitea
        description: Git Repository (CT 2012)
        icon: hl-gitea
        url: http://10.10.20.12:3000

  - name: Network & Infrastructure
    icon: fas fa-network-wired
    displayData:
      cols: 2
      collapsed: false
    items:
      - title: Proxmox VE
        description: Hypervisor Management
        icon: hl-proxmox
        url: https://10.10.10.10:8006

      - title: OPNsense
        description: Firewall & Router
        icon: hl-opnsense
        url: https://10.10.0.1

      - title: Dashy
        description: This Dashboard (CT 4001)
        icon: fas fa-tachometer-alt
        url: http://10.10.40.11:4000

  - name: P2 - Security & Password Management
    icon: fas fa-shield-alt
    displayData:
      collapsed: true
    items:
      - title: Vaultwarden
        description: Password Manager (CT 3010)
        icon: hl-vaultwarden
        url: http://10.10.30.10:8080
EOFCONFIG
    ;;

  2)
    echo ""
    echo "==> Behalte interne URLs (nur im Netzwerk)"
    echo "✅ Config bleibt unverändert"
    echo ""
    echo "Hinweis: Status-Checks funktionieren nur wenn:"
    echo "  • User ist im 10.10.0.0/16 Netzwerk"
    echo "  • Oder via VPN verbunden"
    ;;

  3)
    echo ""
    echo "==> Erstelle Config mit externen URLs (otta.zone)"
    pct exec "$CTID" -- bash -c "cat > $CONFIG_PATH" <<'EOFCONFIG'
---
pageInfo:
  title: RALF Homelab Dashboard
  description: Self-orchestrating homelab infrastructure platform
  logo: https://i.ibb.co/qWWpD0v/astro-dab-128.png
  navLinks:
    - title: RALF GitHub
      path: https://github.com/default82/RALF
    - title: Gitea
      path: https://gitea.otta.zone

appConfig:
  theme: nord-frost
  layout: auto
  iconSize: medium
  language: de
  statusCheck: true
  statusCheckInterval: 300
  disableUpdateChecks: true
  hideComponents:
    - footer

sections:
  - name: P1 - Core Infrastructure
    icon: fas fa-server
    displayData:
      cols: 3
      collapsed: false
    items:
      - title: PostgreSQL
        description: Zentrale Datenbank (CT 2010)
        icon: hl-postgresql
        url: http://10.10.20.10:5432
        statusCheck: false

      - title: Semaphore
        description: CI/CD Orchestration (CT 10015)
        icon: hl-semaphore
        url: https://semaphore.otta.zone
        statusCheck: true

      - title: Gitea
        description: Git Repository (CT 2012)
        icon: hl-gitea
        url: https://gitea.otta.zone
        statusCheck: true

  - name: Network & Infrastructure
    icon: fas fa-network-wired
    displayData:
      cols: 2
      collapsed: false
    items:
      - title: Proxmox VE
        description: Hypervisor Management
        icon: hl-proxmox
        url: https://10.10.10.10:8006

      - title: OPNsense
        description: Firewall & Router
        icon: hl-opnsense
        url: https://10.10.0.1

      - title: Dashy
        description: This Dashboard
        icon: fas fa-tachometer-alt
        url: https://dashy.otta.zone
        statusCheck: true

  - name: P2 - Security & Password Management
    icon: fas fa-shield-alt
    displayData:
      collapsed: true
    items:
      - title: Vaultwarden
        description: Password Manager (CT 3010)
        icon: hl-vaultwarden
        url: https://vault.otta.zone
        statusCheck: true
EOFCONFIG

    echo ""
    echo "⚠️  WICHTIG: Caddy muss korrekt konfiguriert sein!"
    echo "    Siehe: scripts/opnsense/caddy-timeout-fixes.md"
    ;;

  *)
    echo "❌ Ungültige Wahl"
    exit 1
    ;;
esac

echo ""
echo "==> Dashy neu laden (Cache löschen)"
pct exec "$CTID" -- bash -c "pm2 restart all 2>/dev/null || systemctl restart dashy 2>/dev/null || true"

echo ""
echo "✅ FERTIG!"
echo ""
echo "Teste Dashy: http://10.10.40.11:4000"
echo ""
echo "Hinweis: Browser-Cache leeren für sofortige Änderungen"
echo "  • Chrome/Firefox: Strg+Shift+R"
echo "  • Safari: Cmd+Shift+R"
