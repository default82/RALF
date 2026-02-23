# AGENTS.md (Repo-Guide für zukünftige Sessions)

Diese Datei gilt für das gesamte Repository.

## 1) Arbeitsmodus (wichtig)
- Lies **diese Datei zu Beginn jeder Session komplett**.
- Arbeite in kleinen, nachvollziehbaren Änderungen.
- Halte Entscheidungen kurz schriftlich fest (Was wurde geändert? Warum?).
- Bewahre die vorhandene Betriebslogik: **deterministisch, konservativ, nachvollziehbar**.

## 2) Projektüberblick
- `stacks/` enthält die auszuführenden Stacks:
  - Terraform/OpenTofu-Stacks (z. B. `030-minio-lxc`, `100-bootstrap-lxc`)
  - Ansible-Stack (`031-minio-config/playbook.yml`)
- `bootstrap/start.sh` ist der Host-seitige Seed für Proxmox (CT erstellen/starten, Toolchain, Repo, Secrets, Runner).
- `bootstrap/runner.sh` orchestriert die Stack-Ausführung im CT (`tofu plan/apply`, `ansible-playbook` bzw. Syntax-Check).
- `inventory/hosts.ini` wird von Ansible-Stacks genutzt.
- `docs/` enthält die normativen Leitplanken (Charta, Zielbild, Betriebsverfassung).

## 3) Architektur- und Betriebsprinzipien
- **LXC-first**, keine Docker-Einführung.
- Netzwerk basiert auf `10.10.0.0/16`.
- Sicherheit/Robustheit vor "cleveren" Kurzlösungen.
- Keine stillen Breaking Changes in Bootstrap- oder Runner-Logik.
- Bestehende Umgebungsvariablen und Defaults respektieren (Start-/Runner-Skripte sind darauf ausgelegt).

## 4) Konventionen im Code
### Shell (`bootstrap/*.sh`)
- Shebang + `set -euo pipefail` beibehalten.
- Keine unnötigen Abhängigkeiten einführen.
- Idempotenz bewahren (wiederholtes Ausführen darf nicht unerwartet zerstören).
- Bestehende Toggle-Flags (`NO_*`, `AUTO_APPLY`, `START_AT`, `ONLY_STACKS`) nicht brechen.

### Terraform/OpenTofu (`*.tf`)
- Vorhandenen Stil beibehalten (klare Blöcke, sinnvolle Defaults, sensitive Variablen markieren).
- Provider-/Version-Pinning nicht ohne Grund aufweichen.
- Änderungen an IPs/VMIDs/CTIDs bewusst und dokumentiert durchführen.

### Ansible (`stacks/*/playbook.yml`)
- Idempotente Tasks bevorzugen.
- `become`, Dateirechte und Besitzverhältnisse explizit halten.
- Bei secret-relevanten Dateien restriktive Rechte (`0600`) beibehalten.

### Dokumentation
- Kurz, klar, operativ nützlich.
- Deutsche Sprache ist in diesem Repo bevorzugt.

## 5) Validierung vor Abschluss
Führe – passend zur Änderung – so viel wie möglich aus:
- Shell-Syntax:
  - `bash -n bootstrap/start.sh bootstrap/runner.sh`
- Terraform/OpenTofu-Format (je Stack mit `.tf`):
  - `tofu fmt -check -recursive`
- Ansible-Syntax:
  - `ansible-playbook -i inventory/hosts.ini --syntax-check stacks/031-minio-config/playbook.yml`

Wenn Tools in der Umgebung fehlen: klar als Einschränkung dokumentieren.

## 6) Änderungsschwerpunkte (Risiko-Hotspots)
- `bootstrap/start.sh`: beeinflusst CT-Lebenszyklus, Toolchain und Secrets-Injektion.
- `bootstrap/runner.sh`: steuert Reihenfolge und Art der Stack-Ausführung.
- `stacks/030-minio-lxc/main.tf`: produktive MinIO-LXC-Provisionierung.
- `stacks/031-minio-config/playbook.yml`: MinIO-Service-Installation inkl. systemd/Env-Handling.

## 7) Nicht tun
- Keine Secrets im Klartext ins Repo schreiben.
- Keine ad-hoc Strukturänderungen ohne Dokumentation.
- Keine impliziten Annahmen über produktive Erreichbarkeit externer Dienste.
- Keine großflächigen Refactorings ohne klaren Mehrwert und Tests.

## 8) Erwartung an Commit-/PR-Qualität
- Kleine, thematisch fokussierte Commits.
- Commit-Message mit Zweck + Kontext.
- PR-Beschreibung mit:
  - Ausgangslage
  - Änderung
  - Risiken
  - Validierung
