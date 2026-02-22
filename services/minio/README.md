# MinIO

S3-kompatibler Object Storage (ohne Docker), betrieben als systemd service.

## Ziele (v1)
- Single-Node MinIO für Homelab (später erweiterbar)
- TLS via Caddy/OPNsense *später* (v1 erstmal HTTP intern)
- Keine Secrets im Repo (ADR-0001)

## Ports
- API: 9000/TCP
- Console: 9001/TCP

## Daten
- Datenpfad: /var/lib/minio
- Config/Env: /etc/default/minio (liegt nicht im Repo; Template vorhanden)

## Runbooks
- ./runbooks/bootstrap.md
- ./runbooks/upgrade.md
- ./runbooks/backup-restore.md
