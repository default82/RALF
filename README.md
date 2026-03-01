# RALF

<<<<<<< HEAD
RALF ist eine orchestrierende Instanz für den nachvollziehbaren, stabilen Aufbau und Betrieb eines Proxmox-Homelabs.

## Kanonische Grundlagen

- `docs/CHARTA.md`
- `docs/ZIELBILD.md`
- `docs/BETRIEBSVERFASSUNG.md`

Diese drei Dokumente sind bindend und definieren Zweck, Grenzen, Governance und Betriebsregeln.

## Basisdienste (Initiale Säulen)

- MinIO
- PostgreSQL
- Gitea
- Semaphore
- Vaultwarden
- Prometheus
- n8n
- KI-Instanz (lokal)

## Verbindliche Bootstrap-Reihenfolge

1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore
5. Foundation validieren, danach Erweiterungswellen

## Betriebsprinzipien

- LXC-first
- Docker ausgeschlossen
- Netzwerk: `10.10.0.0/16`
- Gatekeeping: `OK | Warnung | Blocker`
- Nachvollziehbarkeit vor Autonomie
- Stabilität vor Komplexität
=======
RALF ist ein Homelab-/Infra-Repository fuer den Aufbau und Betrieb einer orchestrierten Plattform auf Proxmox.

Der aktuelle Fokus ist ein reproduzierbarer Bootstrap mit fruehem Handover zu `Semaphore`:

- `MinIO` fuer S3-kompatiblen Remote-State
- `PostgreSQL` als gemeinsame Datenbank
- `Gitea` als internes Git-Repository
- `Semaphore` als Ausfuehrungs- und Orchestrierungsplattform

Danach werden weitere Dienste ueber Semaphore-Tasks ausgerollt (u. a. `Vaultwarden`, `n8n`, `Synapse`, `Mail`, `exo`).

## Festgelegte Basiswerte (2026-02-28)

- Primaere Domain: `otta.zone`
- Netzwerk: `10.10.0.0/16`
- Bootstrap-Netz (temporaer): `10.10.250.0/24`
- Bootstrap-Lifecycle: explizit `ephemeral`, nach Erfolg stoppen und manuell loeschen
- Foundation (Welle 1): `PostgreSQL`, `Gitea`, `Semaphore`, `Prometheus`, `Vaultwarden`
- Welle 2: `n8n`, `Exo`, `Ollama`, `Synapse+Element`
- Kanonische Variablen/Policy: `bootstrap/VARS.md`
- Kanonische Checks/Gates: `bootstrap/CHECKS.md`
- Beispiel-Answers fuer diesen Stand: `bootstrap/examples/answers.otta.zone.yml`

## Zielbild (Auszug)

- Infrastruktur mit `OpenTofu` + `Terragrunt`
- Konfiguration mit `Ansible`
- Secrets aktuell ueber `.env`-Dateien (spaeter Richtung `Vaultwarden`)
- Schrittweise Smokes/Healthchecks nach jedem Deployment-Schritt

## Wichtige Verzeichnisse

- `bootstrap/` - Bootstrap, Runner, Smokes, Runbooks
- `stacks/` - einzelne Infra-/Config-Stacks (LXC + Dienstkonfiguration)
- `inventory/` - Ansible-Inventar

## Einstieg

### Runner (lokal, aktueller Stand)

```bash
bash bootstrap/runner.sh --answers-file bootstrap/examples/answers.otta.zone.yml --outputs-dir ./outputs
```

Optional mit Gate + Apply:

```bash
ACK=DEPLOY bash bootstrap/runner.sh --apply --outputs-dir ./outputs
```

Hinweis: `--apply` fuehrt jetzt echte `pct create/start`-Provisionierung fuer Foundation + Welle 2 aus
(`postgres`, `gitea`, `semaphore`, `prometheus`, `vaultwarden`, `n8n`, `minio`, `exo_*`, `ollama_llm`, `matrix_element`).
Der Runner schreibt dabei u. a. `checkpoints.json`, `cleanup_manifest.json`, `handover_report.json`, `endpoints.md`.

### Seed + Runner (Stufe A -> B)

```bash
bash bootstrap/start.sh --answers-file bootstrap/examples/answers.otta.zone.yml --outputs-dir ./outputs
```

Mit Integritaetspruefung (SHA256) fuer den Runner:

```bash
RUNNER_SHA256="<sha256_von_bootstrap_runner.sh>" \
bash bootstrap/start.sh --runner-path bootstrap/runner.sh --verify-only
```

### Bootstrap One-Liner (Quick Start, unsicher)

```bash
curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh | bash
```

Fuer interaktive TUI-Runs (empfohlen bei Erststart) funktioniert auch `| bash`, robuster ist aber:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh)"
```

### Parametrisierter One-Liner

```bash
PROVISIONER=host PROFILE=ops NETWORK_CIDR=10.10.0.0/16 BASE_DOMAIN=otta.zone TUI=1 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh)"
```

Mit separatem Output-Verzeichnis (z. B. fuer Vergleiche zwischen Runs):

```bash
PROVISIONER=host YES=1 APPLY=1 OUTPUTS_DIR=/tmp/ralf-bootstrap-run1 \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh)"
```

Unterstuetzte ENV-Parameter (`bootstrap/start.sh` -> `ralf bootstrap`):

- `PROVISIONER=proxmox_pct|host|lxd` (autodetect: `pct` -> `proxmox_pct`, `lxc` -> `lxd`, sonst `host`)
- `PROFILE`
- `NETWORK_CIDR`
- `BASE_DOMAIN`
- `CT_HOSTNAME`
- `TUI=1|0`
- Default: `TUI=1`, wenn TTY vorhanden und `NON_INTERACTIVE!=1` (grafische TUI via `dialog`/`whiptail`, sonst Prompt-Fallback)
- `HOST_PVE_ENV` (Pfad zu Proxmox-API-Secrets auf dem Host)
- `SSH_PRIVKEY_FILE` / `SSH_PUBKEY_FILE` (Pfade fuer ralf SSH-Key)
- `NON_INTERACTIVE=1|0`
- `YES=1|0`
- `FORCE=1|0`
- `ANSWERS_FILE`
- `EXPORT_ANSWERS`
- `OUTPUTS_DIR`

Beispiel fuer Answers-Datei:

- `bootstrap/examples/answers.otta.zone.yml` (empfohlen fuer den aktuellen Zielstand)

Provisioner-Status aktuell:

- `proxmox_pct`: produktiv (delegiert an `bootstrap/adapters/proxmox_pct.sh`)
  - TUI zeigt Quellen/Pfade (Secrets, `pve.env`, SSH-Key), erlaubt Pfadwahl und SSH-Key-Generierung
- `host`: konservativer Minimal-Adapter (legt lokales Workspace-Layout an, keine destruktiven Host-Aenderungen)
  - erzeugt `.ralf-host/bin/ralf-host-runner` mit `--check`, `--dry-run`, `--status`, `--artifacts`, `--json`, `--quiet`, guarded `--run` (default non-apply)
- `lxd`: konservativer Minimal-Adapter (Artefakte + Gatekeeping, erstellt LXD-Instanz falls fehlend und stempelt `user.ralf.*` Metadaten)
  - schreibt zusaetzliche LXD-Artefakte in `OUTPUTS_DIR/lxd/` (Plan + target/applied Metadata)

Phase-1-Cleanroom-Test (MinIO -> PostgreSQL -> Gitea -> Semaphore):

```bash
bash bootstrap/cleanroom-phase1.sh
```

Ab Phase 1 (Semaphore-first Betrieb):

- Runbook: `bootstrap/RUNBOOK-SEMAPHORE.md`
- Template-Runner: `bootstrap/sem-run-template.sh`

Beispiele:

```bash
./bootstrap/sem-run-template.sh --list
./bootstrap/sem-run-template.sh "RALF Phase1 Smoke"
./bootstrap/sem-run-template.sh --json --no-wait "RALF Communication Apply"
```

## Dokumentation

- `bootstrap/README.md` - sichere Startmodi (`SHA256`, `minisign`) und Maintainer-Workflow
- `bootstrap/RUNBOOK.md` - Bootstrap/Transition (`MinIO -> PostgreSQL -> Gitea -> Semaphore`)
- `bootstrap/RUNBOOK-SEMAPHORE.md` - Betrieb ab Phase 1 (Semaphore-first)
- `bootstrap/ARCHITEKTUR.md`, `bootstrap/CHECKS.md`, `bootstrap/VARS.md`

## Hinweis

Das Repository ist auf einen konkreten Homelab-Kontext zugeschnitten (Netze, IP-Schema, Proxmox-Node, Domains). Fuer andere Umgebungen muessen Variablen/Secrets/Inventar angepasst werden.
>>>>>>> f200d596326529e49fcd13e611cc042e296ea1ba
