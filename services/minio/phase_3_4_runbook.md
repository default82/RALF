# Phase 3/4 Runbook MinIO

## Phase 3: Proxmox Deployment (pct)

### Host-Kommandos

```bash
cd /root/RALF
bash services/minio/proxmox_pct_create.sh
```

### Vollautomatisch inkl. Phase 4+5

```bash
cd /root/RALF
bash services/minio/deploy_and_smoke.sh
```

### Optional: explizite Parameter

```bash
CTID=3010 \
HOSTNAME=minio \
IP_CIDR=10.10.30.10/16 \
GATEWAY=10.10.0.1 \
BRIDGE=vmbr0 \
TEMPLATE_STORAGE=local \
TEMPLATE_NAME=ubuntu-24.04-standard_24.04-1_amd64.tar.zst \
ROOTFS_STORAGE=local-lvm \
ROOTFS_SIZE_GB=8 \
DATA_STORAGE=local-lvm \
DATA_SIZE_GB=128 \
bash services/minio/proxmox_pct_create.sh
```

## Phase 4: Automatische Konfiguration im Container

### install.sh ausrollen und ausfuehren

```bash
cd /root/RALF
pct push 3010 services/minio/install.sh /root/install-minio.sh --perms 750
pct exec 3010 -- bash /root/install-minio.sh
```

### Optional: Checksums fuer Binary-Pinning erzwingen

```bash
pct exec 3010 -- env \
  MINIO_SHA256="<sha256_minio_binary>" \
  MC_SHA256="<sha256_mc_binary>" \
  bash /root/install-minio.sh
```

## Firewall-Anforderungen

- Datei auf Proxmox Host: `/etc/pve/firewall/3010.fw`
- Vorlage: `configs/minio/3010.fw.example`

## TLS/Reverse Proxy TODO Stub

- TLS-Termination auf dediziertem Reverse Proxy (z. B. Caddy/Nginx/Traefik)
- interner DNS auf `minio.<LAB_DOMAIN>`
- optional direkter Zugriff auf `9000/9001` nur fuer Proxy-Netz

`Statusobjekt`
```json
{
  "step_id": "minio_phase_3_4_deploy",
  "result": "OK",
  "summary": "Automatisierbare pct-Bereitstellung und non-interactive Installationspfad fuer MinIO sind bereitgestellt.",
  "ip": "10.10.30.10",
  "ctid": 3010,
  "funktionsgruppe_x": 30,
  "dependencies": [
    "services/minio/proxmox_pct_create.sh",
    "services/minio/install.sh",
    "configs/minio/3010.fw.example"
  ],
  "next_actions": [
    "Phase 5 Smoke ausfuehren",
    "DNS + TLS TODO umsetzen"
  ]
}
```
