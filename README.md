# RALF

RALF ist eine orchestrierende Instanz für den nachvollziehbaren, stabilen Aufbau und Betrieb eines Proxmox-Homelabs.

## Kanonische Grundlagen

- `docs/CHARTA.md`
- `docs/ZIELBILD.md`
- `docs/BETRIEBSVERFASSUNG.md`

Diese drei Dokumente sind bindend und definieren Zweck, Grenzen, Governance und Betriebsregeln.

## Basisdienste (Initiale Säulen)

- MinIO
- PostgreSQL
- Gitea
- Semaphore
- Vaultwarden
- Prometheus
- n8n
- KI-Instanz (lokal)

## Verbindliche Bootstrap-Reihenfolge

1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore
5. Foundation validieren, danach Erweiterungswellen

## Betriebsprinzipien

- LXC-first
- Docker ausgeschlossen
- Netzwerk: `10.10.0.0/16`
- Gatekeeping: `OK | Warnung | Blocker`
- Nachvollziehbarkeit vor Autonomie
- Stabilität vor Komplexität
