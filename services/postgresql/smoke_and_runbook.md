# PostgreSQL Smoke + Runbook Stub

## Smoke (Phase 5)

### Lokal im LXC

```bash
sudo bash /opt/ralf/postgresql_smoke.sh local
```

### Remote vom Runner-Host

```bash
export PGPASSWORD="${RALF_POSTGRES_RALF_USER_PASSWORD}"
bash scripts/smoke/postgresql_smoke.sh remote
```

## Gate 4

- `OK`: service active, socket query ok, tcp query ok, status table vorhanden
- `Warnung`: service laeuft, aber remote query instabil/timeouts
- `Blocker`: service down / auth fail / table fehlt

`Statusobjekt`
```json
{
  "step_id": "postgres_phase_5_smoke",
  "result": "WARNUNG",
  "summary": "Smoke-Artefakte erstellt; Lauf ist blockerfrei erst nach abgeschlossener Provision+Deploy auf Ziel-LXC.",
  "artifacts": [
    "scripts/smoke/postgresql_smoke.sh",
    "services/postgresql/smoke_and_runbook.md"
  ],
  "next_actions": [
    "LXC provisionieren und Ansible deploy ausfuehren",
    "lokalen + remote smoke ausfuehren und Ergebnis protokollieren"
  ]
}
```
