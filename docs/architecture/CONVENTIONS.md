# Conventions (v1)

## Repo
- `main` ist die Quelle der Wahrheit.
- Keine Secrets im Repo.
- Alles idempotent: mehrfach laufen lassen darf nichts kaputt machen.

## Naming
- Postgres Roles enden auf `_user`, DBs enden auf `_db` (deine Regel).
- RAM/Storage planen in Zweierpotenzen.

## Layout
- `scripts/` enthält ausführbare Helfer (bash, `set -euo pipefail`).
- `ansible/` nur Ansible (Playbooks/Roles/Collections).
- `stacks/` OpenTofu Root-Module.
- `terragrunt/` Terragrunt Live Config (falls aktiv genutzt).
