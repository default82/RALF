# RALF

RALF ist ein freigabegeführtes Infrastruktur-Betriebssystem für ein Proxmox-Homelab.

## Kanonische Grundlagen

- `docs/CHARTA.md`
- `docs/ZIELBILD.md`
- `docs/BETRIEBSVERFASSUNG.md`

Diese drei Dokumente sind bindend.

## Release-Ready Snapshot

- Stand: 2026-03-01
- `docs/CHARTA.md`: Version 1.2 – Kanonisch (MVP)
- `docs/ZIELBILD.md`: Version 1.2 – Kanonisch (MVP)
- `docs/BETRIEBSVERFASSUNG.md`: Version 1.2 – Kanonisch (MVP)

## Versionierungsregel (Kanon)

- Patch (`x.y.z`): reine Sprach-/Formatkorrekturen ohne inhaltliche Regeländerung.
- Minor (`x.y`): neue Regel, neuer Prozessschritt oder geänderte Reihenfolge.
- Major (`x`): grundlegender Governance-Wechsel (Rollen, Gate-Logik, Geltungsbereich).
- Bei Änderungen an Charta/Zielbild/Betriebsverfassung wird die Version im jeweiligen Dokument und im Snapshot aktualisiert.

## Foundation (verbindliche Reihenfolge)

1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Danach folgen Foundation-Services (`Vaultwarden`, `Prometheus`) und Erweiterungen (`n8n`, KI).
Details zu Phase 2/3 stehen in `docs/ZIELBILD.md`.

## Start (ein Befehl aus Bash)

Empfohlen direkt auf dem Proxmox-Knoten:

```bash
bash bootstrap/start.sh
```

Das Skript führt eine einfache interaktive Abfrage durch und startet danach den `bootrunner`.

## Best-Practice Startpfad

1. Erst im Plan-Modus starten (Default):

```bash
bash bootstrap/start.sh
```

2. Danach bewusst mit Apply starten:

```bash
bash bootstrap/start.sh --apply
```

3. Für automatisierte Läufe ohne Rückfragen:

```bash
bash bootstrap/start.sh --apply --yes --non-interactive --config bootstrap/bootstrap.env
```

Hinweis: Die eigentliche Deploy-Logik hängt an Hook-Skripten unter `bootstrap/hooks/*.sh`.
Die Core-Hooks `010` bis `040` führen im `--apply` Modus idempotente LXC-Provisionierung via `pct` aus.
Hooks `050` bis `090` decken Foundation-Services und Erweiterungen ab.

## Modulare Bootstrap-Struktur

Die Installation und das Deployment sind in wiederverwendbare Module getrennt:

- `bootstrap/lib/hook_module.sh`: gemeinsamer Hook-Runner für standardisierte LXC-Services
- `bootstrap/lib/phase_catalog.sh`: deklarative Hook-Reihenfolge je Phase
- `bootstrap/hooks/*.sh`: service-spezifische Konfiguration + optionale Zusatzlogik

Dadurch bleibt die Ausführungsreihenfolge stabil, während neue Services mit weniger dupliziertem Code ergänzt werden können.

## Smoke-Validierung

Nach einem erfolgreichen Deploy können alle Services mit einem Befehl geprüft werden:

```bash
bash bootstrap/validate.sh --config bootstrap/bootstrap.env
```

Das Skript prüft für jeden Service, ob der LXC-Container läuft, der Dienst aktiv ist und der Port erreichbar ist.
Ergebnisse werden in `$RUNTIME_DIR/smoke-results.jsonl` abgelegt.

## Leitplanken

- LXC-first
- Netzwerkstandard: `10.10.0.0/16`
- Gatekeeping: `OK | Warnung | Blocker`
- Nachvollziehbarkeit vor Autonomie
- Stabilität vor Geschwindigkeit

## Begriffskarte

- Foundation: MinIO, PostgreSQL, Gitea, Semaphore als Kernschicht.
- Foundation-Services: Vaultwarden und Prometheus als Basis-Betriebsdienste.
- Erweiterung: n8n und KI-Dienste nach erfolgreicher Foundation-Validierung.
- Phase: klar abgegrenzter Umsetzungsabschnitt mit eigenem Done-Kriterium.
- Gate: Abschlussstatus eines Schritts (`OK`, `Warnung`, `Blocker`).
- Nachweis: dokumentiertes Ergebnis einer Änderung (Entscheidung, Ergebnis, Gate-Status).

## Betriebsmodus

- Jede relevante Änderung folgt Entscheidungsweg + Gate-Status.
- Jede Phase gilt erst als abgeschlossen mit Nachweis/Artefakten.
- Ab stabiler Foundation: `Semaphore-first` für wiederholbare Ausführung.

## Merge-Gate

Für Pull Requests gilt ein verbindliches Merge-Gate über:

- `.github/pull_request_template.md`
- `.github/workflows/merge-gate.yml`
- `.github/workflows/issue-labeler.yml`
- `.github/workflows/validate-ci.yml`

Für neue Tickets stehen strukturierte Issue-Formulare bereit unter:

- `.github/ISSUE_TEMPLATE/foundation-task.yml`
- `.github/ISSUE_TEMPLATE/extension-task.yml`
- `.github/ISSUE_TEMPLATE/epic.yml`

Aktive Pflichtprüfungen:

- PR-Body enthält `Gate-Status: OK|Warnung|Blocker`
- PR-Body enthält einen Nachweis-Abschnitt
- Bash-Syntaxcheck für `bootstrap/**/*.sh`
- Secret-Guard gegen versehentlich committed Credentials
- Foundation-vor-Extension Regel bei PRs mit Erweiterungs-Deploypfaden
- Dry-Run Checkrun fuer `bootstrap/validate.sh`

Empfohlene lokale Vorprüfung:

```bash
bash -n bootstrap/start.sh bootstrap/bootrunner.sh bootstrap/validate.sh
bash bootstrap/validate.sh --dry-run --runtime-dir /tmp/ralf-runtime
```
