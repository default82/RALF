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

- `bootstrap/RUNBOOK.md` - Bootstrap/Transition (`MinIO -> PostgreSQL -> Gitea -> Semaphore`)
- `bootstrap/RUNBOOK-SEMAPHORE.md` - Betrieb ab Phase 1 (Semaphore-first)
- `bootstrap/ARCHITEKTUR.md`, `bootstrap/CHECKS.md`, `bootstrap/VARS.md`

## Hinweis

Das Repository ist auf einen konkreten Homelab-Kontext zugeschnitten (Netze, IP-Schema, Proxmox-Node, Domains). Fuer andere Umgebungen muessen Variablen/Secrets/Inventar angepasst werden.
