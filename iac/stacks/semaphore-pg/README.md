# Stack: semaphore-pg (Playground)

Dieser Stack stellt Semaphore als Runner bereit. Semaphore ist der erste Dienst,
weil es die Grundlage für alle weiteren automatisierten Deployments ist.

## Zone
Playground

## Zweck / Definition of Done
- Semaphore UI ist intern erreichbar
- Ein Bootstrap-Job kann das Repo auschecken und Scripts ausführen (Smoke)
- Toolchain kann installiert/validiert werden (OpenTofu, Git, curl, jq …)

## Inputs (geplant)
- Proxmox Node / API Zugang (über Runner-Secrets)
- CT-ID, Hostname, IP, Ressourcen (CPU/RAM/Disk)
- Ubuntu LTS Template
- Netzwerk: statische IP, GW/DNS via OPNsense

## Outputs (geplant)
- CT-ID
- Hostname
- IP-Adresse
- URL (intern)

## Tests
- `tests/bootstrap/smoke.sh`
- `tests/bootstrap/install-toolchain.sh` (wenn vorhanden)

## Rollback
- Snapshot `pre-install` vor der Installation
- Bei Fehler: rollback snapshot statt „Repair“

## Notizen
Semaphore startet zunächst mit minimaler Persistenz.
Später kann eine Migration/Neuinstallation auf PostgreSQL erfolgen, sobald PostgreSQL (Functional) existiert.

