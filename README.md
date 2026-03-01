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

## Leitplanken

- LXC-first
- Netzwerkstandard: `10.10.0.0/16`
- Gatekeeping: `OK | Warnung | Blocker`
- Nachvollziehbarkeit vor Autonomie
- Stabilität vor Geschwindigkeit

## Betriebsmodus

- Jede relevante Änderung folgt Entscheidungsweg + Gate-Status.
- Jede Phase gilt erst als abgeschlossen mit Nachweis/Artefakten.
- Ab stabiler Foundation: `Semaphore-first` für wiederholbare Ausführung.
