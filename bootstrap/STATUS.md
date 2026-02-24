# Bootstrap Status (Spec vs Current Stand)

Stand: `main` branch (see latest commit in `git log -1`)

## Summary

Der neue Bootstrap-Pfad ist funktionsfaehig und deutlich verbessert:

- `bootstrap/start.sh` = thin launcher (GitHub one-liner geeignet)
- `ralf bootstrap` = CLI mit Phasen, Outputs, Exitcodes
- Provisioner:
  - `proxmox_pct`: produktiv (Legacy-Adapter)
  - `host`: konservativer Minimal-Adapter (idempotent)
  - `lxd`: konservativer Minimal-Adapter (idempotent, create-if-missing + Metadata-Stamping)

## A) Quick Start (unsafe)

Status: `ERFUELLT`

- `curl .../bootstrap/start.sh | bash` unterstuetzt
- Launcher funktioniert mit Defaults
- `PROVISIONER` autodetect implementiert

## B) Parametrisierter One-Liner

Status: `WEITGEHEND ERFUELLT`

Unterstuetzt:

- `PROVISIONER`
- `PROFILE`
- `NETWORK_CIDR`
- `BASE_DOMAIN`
- `CT_HOSTNAME`
- `TUI`
- `NON_INTERACTIVE`
- `YES`
- `FORCE`
- `ANSWERS_FILE`
- `EXPORT_ANSWERS`
- `OUTPUTS_DIR` (zusaetzliche Erweiterung)

Autodetect:

- `pct` -> `proxmox_pct`
- `lxc` -> `lxd`
- sonst `host`

## C) Danger Zone (Pinned Commit + SHA256)

Status: `ERFUELLT`

- Doku vorhanden (`bootstrap/README.md`)
- Hash-Erzeugung fuer Maintainer dokumentiert
- Launcher funktioniert mit gepinntem Commit (`RALF_REF=<commit>`)

## D) Production-ish (Release + minisign)

Status: `TEILWEISE ERFUELLT (Dokumentation ja, Release-Prozess noch manuell)`

Erfuellt:

- Doku fuer Nutzerflow vorhanden (`minisign -Vm`)
- Doku fuer Maintainer (Keygen/Sign) vorhanden

Offen:

- Kein automatisierter Release-Prozess im Repo (z. B. CI-Workflow fuer Release-Artefakte)
- Keine publizierte `minisign` Public-Key-Quelle im Repo dokumentiert (nur Template-Platzhalter)

## E) start.sh Responsibilities

Status: `WEITGEHEND ERFUELLT`

Erfuellt:

1. Self-check (`bash`, `curl`)
2. Repo-Fetch:
   - via `git` wenn vorhanden
   - tarball fallback wenn `git` fehlt
3. Delegation an `./ralf bootstrap`

Zusatz:

- Tarball-URL-Auswahl ist ref-typ-aware (`branch` / `tag` / `commit`)

Einschraenkung:

- Der Legacy-Proxmox-Adapter bleibt intern noch historisch spezialisiert (alte Defaults/Topologie), d. h. nicht alles ist bereits vollstaendig in `profiles/` + `conventions/` ueberfuehrt.

## F) Bootstrap Engine (CLI Contract)

Status: `WEITGEHEND ERFUELLT`

Erfuellt:

- `ralf bootstrap [options]`
- Phasenmodell (Probe, Config merge, Policy, Provisioner, Artifacts, Optional apply)
- Outputs werden immer geschrieben:
  - `probe_report.json`
  - `final_config.json`
  - `checkpoints.json`
  - `answers.yml`
  - `plan_summary.md`
  - `cli_status.json`
- Exitcodes:
  - `0` ok
  - `1` warn
  - `2` blocker/error

Zusatz:

- `adapter_report_file` in `cli_status.json`
- `OUTPUTS_DIR` / `--outputs-dir` fuer Run-Isolation

Offen / Ausbau:

- Vollwertige nicht-Proxmox-Provisioner (host/lxd derzeit konservative Minimal-Adapter)
- Tieferer Config-Merge (komplexes YAML, nested structures, validation)

## G) TUI (optional)

Status: `TEILWEISE ERFUELLT (Policy/Flags ja, UI nein)`

Erfuellt:

- `TUI=1` / `--tui` Flags vorhanden
- `--no-tui`
- `NON_INTERACTIVE=1` deaktiviert TUI
- Gatekeeping/Warnings fuer TTY/NON_INTERACTIVE

Offen:

- Keine echte TUI-Implementierung (nur Schalter/Gating)

## Aktuelle naechste sinnvolle Schritte

1. TUI implementieren oder explizit als bewusst verschoben markieren (Roadmap)
2. `host`-Provisioner von Workspace-Prep Richtung lokalem Runner/Toolchain-Workflow erweitern
3. `lxd`-Provisioner um Netzwerk-/Profile-Konfig (konservativ, idempotent) erweitern
4. Release-Automation fuer `start.sh` + `start.sh.minisig` einfuehren
5. Legacy-Proxmox-Defaults schrittweise in `profiles/` / `conventions/` ueberfuehren
