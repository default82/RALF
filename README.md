# RALF

RALF ist ein Homelab-/Infra-Repository fuer den Aufbau und Betrieb einer orchestrierten Plattform auf Proxmox.

Der aktuelle Fokus ist ein reproduzierbarer Bootstrap mit fruehem Handover zu `Semaphore`:

- `MinIO` fuer S3-kompatiblen Remote-State
- `PostgreSQL` als gemeinsame Datenbank
- `Gitea` als internes Git-Repository
- `Semaphore` als Ausfuehrungs- und Orchestrierungsplattform

Danach werden weitere Dienste ueber Semaphore-Tasks ausgerollt (u. a. `Vaultwarden`, `n8n`, `Synapse`, `Mail`, `exo`).

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
PROVISIONER=host PROFILE=generic_home NETWORK_CIDR=192.168.178.0/24 BASE_DOMAIN=home.lan TUI=1 \
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
- `NON_INTERACTIVE=1|0`
- `YES=1|0`
- `FORCE=1|0`
- `ANSWERS_FILE`
- `EXPORT_ANSWERS`
- `OUTPUTS_DIR`

Beispiel fuer Answers-Datei:

- `bootstrap/examples/answers.generic_home.yml`

Provisioner-Status aktuell:

- `proxmox_pct`: produktiv (delegiert an Legacy-Proxmox-Bootstrap)
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
