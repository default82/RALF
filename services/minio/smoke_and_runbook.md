# MinIO Smoke + Runbook

## Phase 5: Smoke Tests

### A) Service und Ports

```bash
pct exec 3010 -- systemctl is-active minio
pct exec 3010 -- systemctl --no-pager --full status minio
pct exec 3010 -- ss -lntp
```

### B) Health Endpoints

```bash
pct exec 3010 -- curl -fsS http://127.0.0.1:9000/minio/health/live
pct exec 3010 -- curl -fsS http://127.0.0.1:9000/minio/health/ready
```

### C) Upload/Download + Versioning Rollback

```bash
cd /root/RALF
pct push 3010 services/minio/smoke.sh /root/minio-smoke.sh --perms 750
pct exec 3010 -- bash /root/minio-smoke.sh
```

## Bucket-Setup und Pruefung mit mc

```bash
pct exec 3010 -- bash -lc 'source /root/ralf-secrets/minio.generated && \
  mc alias set minio_local http://127.0.0.1:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" && \
  mc ls minio_local/ && \
  mc version info minio_local/ralf-state'
```

## Objekt-Namensschema (RALF)

- `tofu/<stack>/state.tfstate`
- `tofu/<stack>/plan.json`
- `runs/<runner>/<run-id>/report.json`

`Statusobjekt`
```json
{
  "step_id": "minio_phase_5_smoke",
  "result": "Warnung",
  "summary": "Smoke-Skript und Tests sind bereit. Endgueltiges Resultat ist OK erst nach Lauf auf realem Ziel-LXC.",
  "ip": "10.10.30.10",
  "ctid": 3010,
  "funktionsgruppe_x": 30,
  "dependencies": [
    "services/minio/smoke.sh",
    "laufender MinIO Dienst"
  ],
  "next_actions": [
    "Smoke auf CTID 3010 ausfuehren",
    "Ergebnis im finalen Statusobjekt auf OK/Warnung/Blocker setzen"
  ]
}
```
