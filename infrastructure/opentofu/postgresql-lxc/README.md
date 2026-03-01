# OpenTofu: PostgreSQL LXC (Proxmox)

## Scope

Provisionierung (nur Infrastruktur) fuer `postgres-ops` als Proxmox-LXC.
Konfiguration folgt getrennt via Ansible.

## Provider

- `bpg/proxmox`

## Lauf

```bash
cd infrastructure/opentofu/postgresql-lxc
cp terraform.tfvars.example terraform.tfvars
# Werte eintragen (ohne Secrets im Repo)
export TF_VAR_proxmox_api_token="<vaultwarden_ref_or_env_injected>"
export TF_VAR_proxmox_endpoint="https://<pve-host>:8006/api2/json"
tofu init
tofu plan
```

## Gate 2

- `OK`: Plan ohne Drift/Fehler erzeugt
- `Warnung`: Plan erzeugt, aber Template-Download/Storage unklar
- `Blocker`: API Token/Endpoint fehlen oder Provider init fehlschlaegt
