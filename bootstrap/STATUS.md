# Bootstrap Status

Stand: 2026-02-28

## Kurzfazit

Die Planungsbasis fuer den neuen RALF-Bootstrap ist jetzt als verbindliche
Dokumentations-Spezifikation im Repo abgelegt.

Aktueller Scope dieses Repos:

- Architektur- und Policy-Definitionen sind konkretisiert
- Variablenkatalog + Beispiel-Answers sind vorhanden
- Gatekeeping- und Artefakt-Vertrag sind dokumentiert
- Seed-Launcher ist implementiert (`bootstrap/start.sh`)
- Runner ist implementiert (`bootstrap/runner.sh`)
- Foundation + Welle 2 CT-Provisionierung kann per `pct` laufen (`--apply`)

Noch offen:

- externe Runner-Bundle-Distribution (Release-Assets + Signaturfluss) final anbinden
- Service-Konfiguration innerhalb der CTs (Ansible/OpenTofu-Stacks) nach Provisionierung
- automatische Handover-Logik auf Gitea + Semaphore-Seeding
- Welle 2 Deployment- und Verifikationskette (n8n, KI, Matrix/Element, MinIO-Proof via Semaphore)

## Abgedeckte Entscheidungen (2026-02-28)

- LXC-first
- `10.10.0.0/16` als dauerhaftes Netzschema
- `10.10.250.0/24` als temporaeres Bootstrap-Netz
- Foundation-Welle 1 inkl. fester IP-Reservierungen
- Welle 2 (n8n, Exo, Ollama, Matrix/Element) inkl. fester IPs
- Gatekeeping mit `ok/warn/blocker`, Default-Ack und `--yes`/`ACK=DEPLOY`
- Ephemeral-Bootstrap-Lifecycle mit manuellem Delete
- GitHub als Distribution, Gitea als kanonische Wahrheit

## Dokumente (kanonisch)

- `bootstrap/ARCHITEKTUR.md`
- `bootstrap/CHECKS.md`
- `bootstrap/VARS.md`
- `bootstrap/examples/answers.otta.zone.yml`

## Definition of Done (Phase 1)

Phase 1 gilt als erreicht, wenn mindestens:

- Gitea erreichbar und Repo-Seed vorhanden
- Semaphore erreichbar und Templates vorhanden
- n8n erreichbar
- PostgreSQL erreichbar (`ralf_db`, `ralf_user`)

Erst danach gilt "Foundation lebt" fuer die weitere Automation.
