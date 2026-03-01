# Bootstrap (OpenTofu)

Dieses Verzeichnis ist der Startpunkt für den initialen Aufbau im Homelab.

## Reihenfolge (MVP)

1. `stacks/030-minio-lxc` ausrollen (State-Backend bereitstellen)
2. Bucket `ralf-state` in MinIO anlegen
3. `bootstrap/infra` mit S3-Backend initialisieren
4. `stacks/100-bootstrap-lxc` ausrollen

## Voraussetzungen

- OpenTofu installiert (`tofu`)
- Proxmox API Token vorhanden
- SSH Public Key für Container Login

## Beispielablauf

```bash
cd stacks/030-minio-lxc
tofu init
tofu plan \
  -var="pm_api_url=https://10.10.10.10:8006/api2/json" \
  -var="pm_api_token_id=<token-id>" \
  -var="pm_api_token_secret=<token-secret>" \
  -var="node_name=pve-deploy" \
  -var="ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)"
tofu apply
```

Danach kann `bootstrap/ARCHITEKTUR.md` als Remote-State-Definition genutzt werden.