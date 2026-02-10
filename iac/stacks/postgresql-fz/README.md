# Stack: postgresql-fz (Functional)

PostgreSQL ist der **erste Service** im RALF-Bootstrap. Er bildet die persistente
Datenbasis für Semaphore, Gitea und alle weiteren Plattformdienste.

## Zone

Functional

## Zweck / Definition of Done

- PostgreSQL LXC-Container läuft auf Proxmox
- PostgreSQL akzeptiert Verbindungen auf TCP/5432 (intern)
- Ein Test-DB + Test-User kann erstellt werden
- Snapshot `pre-install` existiert für Rollback

## Inputs

- Proxmox Node / API Zugang (über Runner-Secrets)
- CT-ID, Hostname, IP, Ressourcen (CPU/RAM/Disk)
- Ubuntu LTS Template
- Netzwerk: statische IP, GW/DNS via OPNsense

## Outputs

- CT-ID: 2010
- Hostname: svc-postgres
- IP: 10.10.20.10
- Port: 5432

## Tests

- `tests/postgresql/smoke.sh`

## Rollback

- Snapshot `pre-install` vor der Installation
- Bei Fehler: `pct rollback 2010 pre-install`

## Abhängigkeiten

- P0 Netzwerk-Basis (grüne Network Health Checklist)
