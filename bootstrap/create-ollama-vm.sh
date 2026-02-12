#!/usr/bin/env bash
set -euo pipefail

### =========================
### CONFIG
### =========================

# Proxmox
VMID="${VMID:-4013}"
VM_NAME="${VM_NAME:-svc-ollama}"
BRIDGE="${BRIDGE:-vmbr0}"

# Netzwerk
IP_CIDR="${IP_CIDR:-10.10.40.13/16}"
GW="${GW:-10.10.0.1}"
DNS="${DNS:-10.10.0.1}"

# Ressourcen (AI braucht viel!)
MEMORY="${MEMORY:-16384}"  # 16GB RAM
CORES="${CORES:-8}"
DISK_GB="${DISK_GB:-100}"

# Cloud Image
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
CLOUD_IMAGE="/var/lib/vz/template/iso/ubuntu-24.04-cloudimg.img"

### =========================
### Helpers
### =========================

log() { echo -e "\n==> $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1"; exit 1; }
}

### =========================
### Preconditions
### =========================

need_cmd qm
need_cmd wget

### =========================
### 1) Download Cloud Image
### =========================

if [ ! -f "$CLOUD_IMAGE" ]; then
  log "Download Ubuntu 24.04 Cloud Image"
  wget -O "$CLOUD_IMAGE" "$CLOUD_IMAGE_URL"
fi

### =========================
### 2) Create VM
### =========================

if qm status "$VMID" >/dev/null 2>&1; then
  log "VM ${VMID} existiert bereits, lösche..."
  qm stop "$VMID" 2>/dev/null || true
  sleep 2
  qm destroy "$VMID"
fi

log "Erstelle VM ${VMID}"

qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1 \
  --ostype l26 \
  --cpu host

# Import Cloud Image als Disk
log "Importiere Cloud Image"
qm importdisk "$VMID" "$CLOUD_IMAGE" local-lvm

# Attach Disk
log "Konfiguriere Storage"
qm set "$VMID" --scsihw virtio-scsi-pci --scsi0 "local-lvm:vm-${VMID}-disk-0"
qm set "$VMID" --boot c --bootdisk scsi0

# Resize Disk
qm resize "$VMID" scsi0 "${DISK_GB}G"

# Cloud-Init
log "Konfiguriere Cloud-Init"
qm set "$VMID" --ide2 local-lvm:cloudinit
qm set "$VMID" --ipconfig0 "ip=${IP_CIDR},gw=${GW}"
qm set "$VMID" --nameserver "$DNS"
qm set "$VMID" --ciuser root
qm set "$VMID" --cipassword "$(openssl rand -base64 16)"
qm set "$VMID" --sshkeys /root/.ssh/authorized_keys 2>/dev/null || true

# Autostart
qm set "$VMID" --onboot 1

### =========================
### 3) Start VM
### =========================

log "Starte VM ${VMID}"
qm start "$VMID"

log "Warte auf Boot..."
sleep 30

### =========================
### 4) Install Ollama
### =========================

log "Installiere Ollama in VM"
ssh -o StrictHostKeyChecking=no root@${IP_CIDR%/*} "
apt-get update
apt-get install -y curl zstd
curl -fsSL https://ollama.com/install.sh | sh
systemctl enable ollama
systemctl start ollama
" || echo "WARNUNG: SSH-Installation fehlgeschlagen, manuelle Installation nötig"

### =========================
### 5) Snapshot
### =========================

log "Erstelle Snapshot 'post-install'"
qm snapshot "$VMID" post-install

log "FERTIG"
echo "Ollama VM sollte jetzt laufen:"
echo "  VM-ID: ${VMID}"
echo "  IP: ${IP_CIDR%/*}"
echo "  SSH: ssh root@${IP_CIDR%/*}"
echo "  Ollama API: http://${IP_CIDR%/*}:11434"
