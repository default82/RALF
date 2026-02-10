# Stack: gitea-fz (Functional)

Gitea ist das **selbst-gehostete Git-Repository** im RALF-Homelab.
Es ersetzt GitHub als Remote und wird zur Single Source of Truth fuer IaC, Pipelines und Dokumentation.

## Zone

Functional

## Zweck / Definition of Done

- Gitea LXC-Container laeuft auf Proxmox
- Web UI ist intern erreichbar (HTTP :3000)
- SSH-Clone funktioniert (:2222)
- Nutzt PostgreSQL als Datenbank-Backend
- RALF-Repository ist migriert
- Snapshot `pre-install` existiert fuer Rollback

## Inputs

- Proxmox Node / API Zugang (ueber Runner-Secrets)
- CT-ID, Hostname, IP, Ressourcen (CPU/RAM/Disk)
- Ubuntu LTS Template
- Netzwerk: statische IP, GW/DNS via OPNsense
- PostgreSQL-Verbindungsdaten (DB + User)

## Outputs

- CT-ID: 2012
- Hostname: svc-gitea
- IP: 10.10.20.12
- HTTP: :3000
- SSH: :2222

## Tests

- `tests/gitea/smoke.sh`

## Rollback

- Snapshot `pre-install` vor der Installation
- Bei Fehler: `pct rollback 2012 pre-install`

## Abhaengigkeiten

- P0 Netzwerk-Basis (gruene Network Health Checklist)
- PostgreSQL (svc-postgres / 10.10.20.10)
