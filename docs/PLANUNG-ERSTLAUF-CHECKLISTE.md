# RALF - Erstlauf Checkliste (Plan -> Apply -> Validate)

Stand: 2026-03-05

## 1. Ziel

Diese Checkliste beschreibt den ersten kontrollierten Umsetzungsdurchlauf auf einem Proxmox-Host,
inklusive erwarteter Artefakte und Gate-Entscheidungen.

## 2. Harte Voraussetzungen (vor Start)

1. Ausfuehrung auf Proxmox-Host mit verfuegbarem `pct` und `pveam`.
2. Gueltige API-Zugangsdaten fuer Apply-Lauf:
   - `PROXMOX_API_TOKEN_ID`
   - `PROXMOX_API_TOKEN_SECRET`
3. SSH-Public-Key-Datei vorhanden:
   - `${RALF_SSH_PUBKEY_FILE}` (Default: `/root/.ssh/ralf_ed25519.pub`)
4. Netzwerk und Adressplan konsistent zu `docs/IP-KONVENTION.md`.
5. Runtime-Verzeichnis beschreibbar (Default: `/opt/ralf/runtime`).

Bei Nichterfuellung von 1-3: `Blocker`.

## 3. Vorpruefung (lokal)

```bash
bash -n bootstrap/start.sh bootstrap/bootrunner.sh bootstrap/validate.sh
bash bootstrap/validate.sh --dry-run --runtime-dir /tmp/ralf-runtime
```

Erwartung:

- kein Syntaxfehler
- Dry-Run erzeugt pruefbare Smoke-Ausgabe

Gate:

- `OK` bei erfolgreicher Vorpruefung
- `Warnung` bei nicht-kritischen Abweichungen mit dokumentierter Folgeaktion
- `Blocker` bei Syntax-/Ablauffehlern

## 4. Plan-Lauf

```bash
bash bootstrap/start.sh --config bootstrap/bootstrap.env
```

Erwartete Ergebnisse:

- Log unter `$RUNTIME_DIR/logs/run-<id>.log`
- Checkpoints unter `$RUNTIME_DIR/checkpoints.jsonl`
- State-Dateien unter `$RUNTIME_DIR/state/*.state`

Mindestens erwartete State-Dateien nach vollem Plan-Lauf:

- `minio.state`
- `postgresql.state`
- `gitea.state`
- `semaphore.state`
- `vaultwarden.state`
- `prometheus.state`
- `n8n.state`
- `ki.state`
- `matrix.state`
- `semaphore-first.state`

Gate:

- `OK` wenn alle Phasen ohne `Blocker` durchlaufen
- `Warnung` bei nachvollziehbaren Abweichungen ohne Sicherheitsrisiko
- `Blocker` bei fehlenden Pflichtartefakten oder abgebrochenen Phasen

## 5. Apply-Lauf (kontrolliert)

```bash
bash bootstrap/start.sh --apply --config bootstrap/bootstrap.env
```

Zusatzhinweise aus Hooks:

- `020-postgresql` erzeugt automatisch `state/postgresql-credentials.env` (Mode 600).
- `085-matrix` erwartet PostgreSQL-Credentials; ohne diese endet Apply mit `Blocker`.
- `090-semaphore-first` verlangt vorhandenen `semaphore.state` und erreichbaren Semaphore-CT.

Gate:

- `OK` bei erfolgreichem Phasenlauf 0-4
- `Warnung` nur mit bewusstem Owner-Weiterentscheid
- `Blocker` bei Service-Init-Fehlern oder fehlenden Vorbedingungen

## 6. Smoke-Validierung

```bash
bash bootstrap/validate.sh --config bootstrap/bootstrap.env
```

Erwartung:

- Ausgabe in `$RUNTIME_DIR/smoke-results.jsonl`
- Servicechecks fuer alle geplanten Dienste inkl. Matrix

Gate:

- `OK` wenn keine fehlgeschlagenen Service-Smokes
- `Warnung` bei teilweisen Fehlersignalen mit dokumentierter Ursache
- `Blocker` bei kritischen Dienstausfaellen

## 7. Mindestnachweise pro Durchlauf

1. Run-Log (`run-<id>.log`)
2. Checkpoints (`checkpoints.jsonl`)
3. Summary (`summary.md`)
4. Smoke-Ergebnisse (`smoke-results.jsonl`)
5. Gate-Entscheidung (`OK|Warnung|Blocker`) mit kurzer Begruendung

## 8. Offene Infrastruktur-Entscheidung

Mehrere Dienste schreiben URLs als `http://<service>.<RALF_DOMAIN>` (z. B. Gitea, Semaphore, Vaultwarden, n8n, Matrix).
Die `*.md`-Quellen legen jedoch keinen verbindlichen DNS-/Ingress-Standard fest.

Fuer den Erstlauf muss festgelegt werden:

- interne DNS-Aufloesung (empfohlen), oder
- temporaere `/etc/hosts`-Aufloesung fuer Testzwecke.

Ohne diese Festlegung sind End-to-End-Clienttests nur eingeschraenkt reproduzierbar (`Warnung`).