# RALF Bootstrap Variablenkatalog

Stand: 2026-02-28

Ziel: Ein einzelnes `answers.yml` als Eingabe. Daraus leitet der Runner
`outputs/final_config.json` ab.

## Konventionen

- Source of truth waehrend des Runs: `answers.yml` + Runtime-Secrets
- Klartext-Secrets nie ins Repo
- Defaults sind konservativ und LXC-first

## Kanonisches Strukturbeispiel

```yaml
global:
  primary_domain: otta.zone
  timezone: Europe/Berlin
  dns_provider: infomaniak

proxmox:
  pve_node: pve-deploy
  storage_template: local:iso
  storage_rootfs: local-lvm
  lxc_template: ubuntu-24.04-standard
  bridge: vmbr0
  template_policy_auto_download: true

network:
  cidr: 10.10.0.0/16
  gateway: 10.10.0.1
  dns_servers:
    - 10.10.0.1
  bootstrap_net: 10.10.250.0/24

ips:
  bootstrap: 10.10.250.10
  postgres: 10.10.20.10
  gitea: 10.10.40.10
  semaphore: 10.10.100.10
  prometheus: 10.10.80.10
  vaultwarden: 10.10.30.10
  n8n: 10.10.100.11
  minio: 10.10.100.20
  exo_coordinator: 10.10.90.10
  exo_worker: 10.10.90.11
  ollama_llm: 10.10.90.20
  matrix_element: 10.10.110.10

resources:
  default:
    cpu: 2
    ram_mb: 512
    disk_gb: 8
  allow_auto_increase: true
  auto_increase_warn: true

identity:
  admin_email: REPLACE_ME
  admin_username: REPLACE_ME
  ssh_pubkey: REPLACE_ME

database:
  preferred: postgresql
  fallback: mariadb
  shared:
    ralf_db_name: ralf_db
    ralf_db_user: ralf_user
  service_db_suffix: _db
  service_user_suffix: _user
  password_min_length: 32

gatekeeping:
  require_ack_default: true
  ack_token: DEPLOY
  allow_non_interactive_yes: true

distribution:
  bootstrap_source: github
  bootstrap_repo: ralf/bootstrap
  github_owner: kolja
  canonical_remote_after_handover: gitea
  integrity_check: sha256

reverse_proxy_dns:
  reverse_proxy: caddy-opnsense
  opnsense_api_base: https://10.10.0.1/
  infomaniak_dns_api_required: true
  hostnames:
    gitea: gitea.otta.zone
    semaphore: semaphore.otta.zone
    prometheus: prometheus.otta.zone
    vault: vault.otta.zone
    n8n: n8n.otta.zone
    minio: minio.otta.zone
    llm: llm.otta.zone
    matrix: matrix.otta.zone
    element: element.otta.zone

bootstrap_lifecycle:
  name_pattern: ralf-bootstrap-<timestamp>
  tags:
    ralf.role: bootstrap
    ralf.lifecycle: ephemeral
    ralf.delete_ok: "true"
  stop_when_done: true
  delete_manual: true

proof:
  service: minio
  group: 100
  minio_buckets:
    - tofu-state
    - terragrunt-state
    - ansible-artifacts
```

## Pflichtfelder

Mindestens gesetzt sein muessen:

- `global.primary_domain`
- `proxmox.pve_node`
- `proxmox.storage_template`
- `network.cidr`
- `network.gateway`
- `identity.admin_email`
- `identity.admin_username`
- `identity.ssh_pubkey`

## Abgeleitete Werte

Der Runner leitet mindestens diese Werte automatisch ab:

- CTID/VMID aus IP (`octet3 + octet4_pad3`)
- Service-DB/User-Namen (`<service>_db`, `<service>_user`)
- Artefaktpfade unter `outputs/`
