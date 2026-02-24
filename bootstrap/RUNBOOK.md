# RALF Bootstrap Runbook (Transition zu Semaphore)

Ziel: frueh auf `MinIO` (Remote State) und danach auf `Semaphore` als Ausfuehrungsplattform wechseln.

## Reihenfolge (verbindlich)

1. `MinIO` deployen (`030`, `031`)
2. `PostgreSQL` deployen (`020`, `021`)
3. `Gitea` deployen (`034`, `035`)
4. `Semaphore` deployen und seeden (`040`, `041`)
5. Ab hier weitere Dienste bevorzugt ueber Semaphore-Templates deployen

## Warum diese Reihenfolge

- `MinIO` zuerst: Remote-State (S3-kompatibel) steht frueh bereit.
- `PostgreSQL` danach: gemeinsame Datenbank fuer Folge-Dienste.
- `Gitea` vor `Semaphore`: internes Repo als Quelle fuer Jobs.
- `Semaphore` danach: zentrale Ausfuehrung, Logs, Wiederholbarkeit, Smoke-Tests.

## Phase 1 lokal/hostseitig ausfuehren

Cleanroom-Test (holt `start.sh` indirekt ueber `phase1-core.sh` aus GitHub und testet nach jedem Schritt):

```bash
cd /root/RALF
bash bootstrap/cleanroom-phase1.sh
```

Manuell (gezielte Phasen):

```bash
cd /root/RALF
AUTO_APPLY=1 START_AT=000 ONLY_STACKS='030-minio-lxc 031-minio-config' bash bootstrap/start.sh
bash bootstrap/smoke.sh minio

AUTO_APPLY=1 START_AT=000 ONLY_STACKS='020-postgres-lxc 021-postgres-config' bash bootstrap/start.sh
bash bootstrap/smoke.sh postgres

AUTO_APPLY=1 START_AT=000 ONLY_STACKS='034-gitea-lxc 035-gitea-config' bash bootstrap/start.sh
bash bootstrap/smoke.sh gitea

AUTO_APPLY=1 START_AT=000 ONLY_STACKS='040-semaphore-lxc 041-semaphore-config' bash bootstrap/start.sh
bash bootstrap/smoke.sh semaphore
```

## Phase 1 Abschlusskriterien

- `bootstrap/smoke.sh phase1` erfolgreich
- Semaphore-Templates existieren (Seed in `041`)
- Mindestens diese Template-Smokes erfolgreich:
  - `RALF Phase1 Smoke`
  - `RALF Vault Smoke`
  - `RALF Communication Smoke`

## Semaphore-Templates ausfuehren (API)

Hinweis: Task-Start erfolgt ueber `POST /api/project/<id>/tasks` mit `{\"template_id\":...}`.
Der alte Pfad `POST /api/project/<id>/templates/<id>/tasks` liefert in der aktuellen Semaphore-Version `404`.

Beispiel (innerhalb des Semaphore-Containers `4010`):

```bash
/root/sem_run_named.sh 'RALF Phase1 Smoke'
/root/sem_run_named.sh 'RALF Vault Smoke'
/root/sem_run_named.sh 'RALF Communication Smoke'
```

## Betriebsmodus nach Phase 1

- Infrastruktur-/Config-Runs bevorzugt ueber Semaphore ausfuehren.
- `bootstrap/start.sh` bleibt als Recovery-/Break-Glass-Pfad erhalten.
- Nach abgeschlossener groesserer Phase immer ein Cleanroom-Test + relevante Smokes ausfuehren.
