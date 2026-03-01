#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# creates/starts LXC bootstrap container in an idempotent way

# --- Config (edit if needed) ---
CTID="${CTID:-10010}"                 # 10.10.100.10 -> 10010
CT_HOSTNAME="${CT_HOSTNAME:-ralf-bootstrap}"
IP_CIDR="${IP_CIDR:-10.10.100.10/16}"
GW="${GW:-10.10.0.1}"
BRIDGE="${BRIDGE:-vmbr0}"

MEM_MB="${MEM_MB:-2048}"
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-32}"

STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE="${TEMPLATE:-ubuntu-24.04-standard_24.04-1_amd64.tar.zst}"

SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

# --- Helpers ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }

need pct
need pveam

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  echo "ERROR: SSH public key not found at $SSH_PUBKEY_FILE" >&2
  exit 1
fi

echo "==> Ensure template exists: ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
if ! pveam list "${TEMPLATE_STORAGE}" | awk '{print $1}' | grep -qx "${TEMPLATE}"; then
  echo "==> Downloading template to ${TEMPLATE_STORAGE}..."
  pveam update >/dev/null
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
else
  echo "==> Template already present."
fi

# Create CT if missing
if ! pct status "${CTID}" >/dev/null 2>&1; then
  echo "==> Creating CT ${CTID} (${CT_HOSTNAME} @ ${IP_CIDR})"
  pct create "${CTID}" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features "nesting=1" \
    --start 0
else
  echo "==> CT ${CTID} already exists. Ensuring config is set."
  # Update relevant settings (idempotent-ish)
  pct set "${CTID}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features "nesting=1" >/dev/null
fi

echo "==> Installing SSH pubkey into CT ${CTID}"
if pct set "${CTID}" --ssh-public-keys "${SSH_PUBKEY_FILE}" >/dev/null 2>&1; then
  echo "==> SSH key installed via pct option."
else
  echo "==> pct --ssh-public-keys not supported, applying key inside container."
  pct start "${CTID}" >/dev/null 2>&1 || true
  KEY_CONTENT="$(tr -d '\r' < "${SSH_PUBKEY_FILE}")"
  pct exec "${CTID}" -- bash -lc "install -d -m 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && grep -qxF '${KEY_CONTENT}' /root/.ssh/authorized_keys || echo '${KEY_CONTENT}' >> /root/.ssh/authorized_keys"
fi

echo "==> Starting CT ${CTID}"
pct start "${CTID}" >/dev/null 2>&1 || true

echo "==> Status:"
pct status "${CTID}"

echo "==> Done."
echo "   Next: pct exec ${CTID} -- bash -lc 'hostname; ip -br a; uname -a'"