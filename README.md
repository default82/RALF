# RALF

RALF ist ein freigabegeführtes Infrastruktur-Betriebssystem für ein Proxmox-Homelab.

## Kanonische Grundlagen

- `docs/CHARTA.md`
- `docs/ZIELBILD.md`
- `docs/BETRIEBSVERFASSUNG.md`

Diese drei Dokumente sind bindend.

## Foundation (verbindliche Reihenfolge)

1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Danach folgen Foundation-Services (`Vaultwarden`, `Prometheus`) und Erweiterungen (`n8n`, KI).
Details zu Phase 2/3 stehen in `docs/ZIELBILD.md`.

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
