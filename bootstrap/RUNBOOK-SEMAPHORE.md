# RALF Runbook ab Phase 1 (Semaphore-first)

Dieses Runbook gilt **nach erfolgreicher Phase 1** (`MinIO`, `PostgreSQL`, `Gitea`, `Semaphore`).

Ziel: weitere Deployments standardisiert ueber `Semaphore` ausfuehren und direkt mit Smokes pruefen.

## Voraussetzungen

- `bootstrap/smoke.sh phase1` erfolgreich
- Semaphore erreichbar: `https://10.10.40.10/`
- Templates wurden durch `041-semaphore-config` geseedet

## Grundregel

1. `Apply`-Template starten
2. passendes `Smoke`-Template starten
3. bei Fehler: Logs in Semaphore pruefen, Fix im Repo, Commit/Push, Template erneut starten

`bootstrap/start.sh` bleibt nur fuer Recovery / Break-Glass.

## Standard-Reihenfolge ab Phase 1

1. `RALF Vault Apply`
2. `RALF Vault Smoke`
3. `RALF Automation Apply`
4. `RALF Automation Smoke`
5. `RALF Communication Apply`
6. `RALF Communication Smoke`
7. `RALF AI Apply`
8. `RALF AI Smoke`

## Einzelservice-Runs (gezielt)

Verwenden bei Fehleranalyse oder kleineren Aenderungen:

- `RALF Vaultwarden Apply`
- `RALF N8N Apply`
- `RALF Synapse Apply`
- `RALF Mail Apply`
- `RALF Exo Apply`

Danach jeweils passenden Gruppen-Smoke starten:

- Vaultwarden -> `RALF Vault Smoke`
- N8N -> `RALF Automation Smoke`
- Synapse/Mail -> `RALF Communication Smoke`
- Exo -> `RALF AI Smoke`

## Empfohlene Deploy-Muster

### Muster A: normale Aenderung an einem Dienst

1. Code aendern
2. Commit + Push
3. passendes Einzelservice-`Apply`
4. passendes Gruppen-`Smoke`

### Muster B: Aenderung an gemeinsam genutzter Basis (z. B. `smoke.sh`, Seeder, Runner)

1. Code aendern
2. Commit + Push
3. `RALF Phase1 Config Apply` (aktualisiert Semaphore-Host-Werkzeuge/Repo)
4. relevante Smokes (`Phase1`, dann betroffene Gruppen)

## Fehlerbehandlung (Standard)

- `tofu`-Fehler: zuerst MinIO/State-Erreichbarkeit und Proxmox-API pruefen
- `ansible`-Fehler: betroffenen Stack direkt ueber Einzelservice-Template wiederholen
- `smoke`-Fehler: zuerst Dienststatus im Ziel-CT, dann Nginx/TLS, dann App-Port
- `Semaphore`-Fehler: `041-semaphore-config` erneut ausrollen

## Cleanroom-Checks pro Phase

Nach einer abgeschlossenen groesseren Phase (z. B. neue Dienstgruppe produktionsreif):

1. `bash bootstrap/cleanroom-phase1.sh`
2. in Semaphore:
   - `RALF Phase1 Smoke`
   - betroffene Gruppen-Smokes

## API-Hinweis (falls manuell automatisiert wird)

Aktuelle Semaphore-Version startet Template-Tasks ueber:

- `POST /api/project/<id>/tasks` mit Body `{"template_id": <id>}`

Nicht mehr verwenden:

- `POST /api/project/<id>/templates/<id>/tasks` (liefert `404`)
