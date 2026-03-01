# MinIO in R.A.L.F. (LXC, ohne Docker)

## Zielbild

MinIO ist der zentrale Object-Store fuer:
- OpenTofu Statefiles
- Planfiles
- Artefakte
- Reports

## Dependency-Transparenz

- Dependencies: `keine` (Startdienst)
- Wird genutzt von:
- `semaphore` (S3 State/Plans/Reports)
- `n8n` (Artefakte)

## Platzierung

- Funktionsgruppe (X): `30` (Backup & Sicherheit)
- IP: `10.10.30.10/16`
- CTID: `3010`
- Hostname: `minio`
- FQDN: `minio.<LAB_DOMAIN>`

## Buckets

- `ralf-state` (Versioning ON)
- `ralf-artifacts`

## Ablauf

1. Vollautomatisch: `services/minio/deploy_and_smoke.sh`
2. Alternativ einzeln: `services/minio/proxmox_pct_create.sh` -> `services/minio/install.sh` -> `services/minio/smoke.sh`

## Wichtige Dateien

- `services/minio/service_card.md`
- `services/minio/phase_3_4_runbook.md`
- `services/minio/smoke_and_runbook.md`
- `services/minio/secrets_policy.md`
- `configs/minio/minio.env.example`
- `configs/minio/minio.service`
- `configs/minio/3010.fw.example`
