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
