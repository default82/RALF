# Ansible – RALF Homelab

Ansible konfiguriert Services **innerhalb** bereits provisionierter LXC-Container.
Die Container selbst werden mit OpenTofu oder Bootstrap-Scripts erstellt.

## Rollen

| Rolle        | Zweck                              |
| ------------ | ---------------------------------- |
| `base`       | Grundzustand: Pakete, NTP, SSH     |
| `postgresql` | PostgreSQL Installation + Config   |
| `gitea`      | Gitea Installation + Config        |

## Playbooks

| Playbook              | Ziel                               |
| --------------------- | ---------------------------------- |
| `bootstrap-base.yml`  | Alle P1-Container standardisieren  |
| `deploy-postgresql.yml` | PostgreSQL deployen              |
| `deploy-gitea.yml`    | Gitea deployen (braucht PG)        |

## Verwendung

```bash
# Vom Semaphore-Runner oder manuell:
cd iac/ansible
ansible-playbook -i inventory/hosts.yml playbooks/deploy-postgresql.yml
```

## Secrets

Secrets werden **nicht** im Repo gespeichert. Sie kommen ueber:
- Semaphore-Variablen (empfohlen)
- `--extra-vars` bei manuellem Aufruf
