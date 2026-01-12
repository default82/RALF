# Infrastructure as Code (IaC)

In diesem Ordner liegen die IaC-Stacks, die Proxmox-LXC-Container und Dienste ausrollen.

## Grundidee
- **OpenTofu** beschreibt Infrastruktur und „Desired State“
- der **State** ist anfangs lokal (später kann ein Backend folgen)
- optional: **Ansible** konfiguriert Services innerhalb der Container

## Konventionen
Jeder Stack hat diese Struktur:

`iac/stacks/<stack-name>/`
- `tofu/` – OpenTofu Dateien (main/variables/outputs/versions)
- `env/` – environment-spezifische Variablen (z.B. playground.tfvars)
- `README.md` – Zweck, Inputs/Outputs, Tests, Rollback, Owner

## Regeln
- Keine Secrets in `*.tfvars` (nur Werte, die nicht geheim sind)
- Secrets kommen über Runner-Variablen (Semaphore)
- Jeder Stack muss Smoke/Acceptance Tests besitzen (siehe `tests/`)
- Jeder Stack muss Rollback-Strategie nennen (Snapshots)

## Bootstrap-Remote
Aktuell ist GitHub das Remote. Später wird dieses Repo nach Gitea umgezogen.
Die Struktur bleibt gleich; nur die Repo-URL im Runner ändert sich.
