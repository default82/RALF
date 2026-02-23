#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# creates/starts LXC bootstrap container in an idempotent way

# --- Config (edit if needed) ---
HOSTNAME="${HOSTNAME:-ralf-bootstrap}"

IP_CIDR="${IP_CIDR:-10.10.100.10/16}"
GW="${GW:-10.10.0.1}"
BRIDGE="${BRIDGE:-vmbr0}"

MEM_MB="${MEM_MB:-2048}"
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-32}"

STORAGE="${STORAGE:-local-lvm}"          # rootfs storage (lvmthin)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"  # vzdump/vztmpl storage (dir)

SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

# Template selection (future-proof)
DIST="${DIST:-ubuntu}"
SERIES="${SERIES:-24.04}"
FLAVOR="${FLAVOR:-standard}"

# --- Helpers ---
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }

need pct
need pveam
need awk
need grep
need sort

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  echo "ERROR: SSH public key not found at $SSH_PUBKEY_FILE" >&2
  exit 1
fi

# --- Derive CTID from IP (last two octets) ---
IP="${IP_CIDR%%/*}"   # 10.10.100.10
O3="$(echo "$IP" | awk -F. '{print $3}')"
O4="$(echo "$IP" | awk -F. '{print $4}')"
CTID="${CTID:-${O3}${O4}}"  # 100 + 10 => 10010 (string concat)

echo "==> Target: CTID=${CTID} HOSTNAME=${HOSTNAME} IP=${IP_CIDR} GW=${GW} BRIDGE=${BRIDGE}"

# --- Resolve latest template (future-proof) ---
echo "==> Refresh template list"
pveam update >/dev/null

echo "==> Resolving latest template for: ${DIST}-${SERIES}-${FLAVOR}"
TEMPLATE="$(pveam available -section system \
  | awk '{print $1}' \
  | grep -E "^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.zst$" \
  | sort -V \
  | tail -n 1)"

if [[ -z "${TEMPLATE}" ]]; then
  echo "ERROR: Could not find a matching template via pveam available." >&2
  echo "Tried pattern: ^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\\.[0-9]+-[0-9]+_amd64\\.tar\\.zst$" >&2
  echo "Hint: pveam available -section system | grep -i ${DIST}" >&2
  exit 1
fi

echo "==> Latest template resolved: ${TEMPLATE}"

# --- Ensure template is cached locally ---
CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ -f "${CACHE}" ]]; then
  echo "==> Template already cached: ${CACHE}"
else
  echo "==> Downloading template to ${TEMPLATE_STORAGE}..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
fi

OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
echo "==> Using ostemplate: ${OSTEMPLATE}"

# --- Create or update CT ---
if ! pct status "${CTID}" >/dev/null 2>&1; then
  echo "==> Creating CT ${CTID} (${HOSTNAME} @ ${IP_CIDR})"
  pct create "${CTID}" "${OSTEMPLATE}" \
    --hostname "${HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features "nesting=1" \
    --start 0
else
  echo "==> CT ${CTID} already exists. Ensuring config is set."
  pct set "${CTID}" \
    --hostname "${HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features "nesting=1" >/dev/null
fi

echo "==> Installing SSH pubkey into CT ${CTID}"
pct set "${CTID}" --ssh-public-keys "${SSH_PUBKEY_FILE}" >/dev/null

echo "==> Starting CT ${CTID}"
pct start "${CTID}" >/dev/null 2>&1 || true

echo "==> Status:"
pct status "${CTID}"

echo "==> Done."
echo "   Next: pct exec ${CTID} -- bash -lc 'hostname; ip -br a; uname -a'"
