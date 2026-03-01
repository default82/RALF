# RALF Bootstrap Checks

Stand: 2026-02-28

## Gatekeeping Contract

Jeder Schritt liefert genau einen Status:

- `ok`: Ausfuehrung sicher fortsetzbar
- `warn`: Fortsetzung nur nach expliziter Bestaetigung
- `blocker`: keine Fortsetzung, Abbruch mit Summary

Ausgabe immer:

- kurzer menschlicher Status
- maschinenlesbare Artefakte in `outputs/`

## Ack-Policy

Default:

- Plan anzeigen
- kurze Bestaetigung einholen

Nicht-interaktive Freigabe:

- Flag: `--yes`
- Env: `ACK=DEPLOY` (Token konfigurierbar)

## Checkpoints

### Checkpoint A (Probe/Preflight)

Mindestpruefungen:

- Runner-Umgebung ist host-nah (`pct` verfuegbar)
- Proxmox-Node/Storage konfigurierbar
- Netz-Parameter valide (`10.10.0.0/16`, Gateway, DNS)
- Pflichtwerte vorhanden (`admin`, SSH-Key, Domain, Distribution/Integrity)

`blocker` Beispiele:

- `pct` fehlt
- ungueltiges CIDR/Gateway
- kritische Secrets/Schluessel nicht verfuegbar

`warn` Beispiele:

- Template fehlt, aber Auto-Download moeglich
- optionale Integritaetsinfo fehlt, fallback verfuegbar

### Checkpoint B (Plan/Gate)

Mindestpruefungen:

- IP-Allocation kollisionsfrei
- CTID-Ableitung eindeutig
- Ressourcen-Plan plausibel (Defaults + begruendete Erhoehungen)
- Stages/Naming valide (`ops`, `dev`, `lab`)

`blocker` Beispiele:

- IP-Kollision
- doppelte CTID
- unzulaessige Stage

`warn` Beispiele:

- RAM-Erhoehung gegenueber Default noetig
- nichtkritische Ports/Proxy-Prechecks unsicher

### Checkpoint C (Apply)

Mindestpruefungen:

- Foundation-LXCs per `pct` erstellt (`postgres`, `gitea`, `semaphore`, `prometheus`, `vaultwarden`)
- Welle-2/Proof-LXCs per `pct` erstellt (`n8n`, `minio`, `exo_*`, `ollama_llm`, `matrix_element`)
- Basis-Metadaten gesetzt (ephemeral/persistent)
- apply-report geschrieben

`blocker` Beispiele:

- `pct create`/`pct start` Fehler
- Storage/Template nicht nutzbar

`warn` Beispiele:

- Retry erfolgreich nach transientem Fehler

### Checkpoint D (Configure/Verify/Handover)

Mindestpruefungen:

- Foundation-Dienste erreichbar
- Repo-Seed in Gitea vorhanden
- Semaphore Projekt/Templates/Keys vorbereitet
- n8n + KI-Komponenten deployed (Welle 2)
- MinIO-Proof via Semaphore laeuft

`blocker` Beispiele:

- Gitea oder Semaphore nicht erreichbar
- Handover auf kanonisches Remote nicht abgeschlossen

`warn` Beispiele:

- Teil-Smoke erfolgreich, aber Zusatzkomponente degradiert

## Artefakt-Vertrag (Pflicht)

Mindestens diese Dateien muessen entstehen:

- `outputs/probe_report.json`
- `outputs/final_config.json`
- `outputs/checkpoints.json`
- `outputs/plan_summary.md`
- `outputs/password_summary.md` (maskiert)
- `outputs/handover_report.json`
- `outputs/endpoints.md`

Ergaenzend fuer Lifecycle:

- `outputs/cleanup_manifest.json`

## Exitcodes

- `0`: Gesamtstatus `ok`
- `1`: Gesamtstatus `warn`
- `2`: `blocker` oder technischer Fehler
