#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# Creates/starts LXC bootstrap container idempotent-ish.

# ---- Config ----
CT_HOSTNAME="${CT_HOSTNAME:-ralf-bootstrap}"   # IMPORTANT: don't use HOSTNAME (env var collision)

IP_CIDR="${IP_CIDR:-10.10.100.10/16}"
GW="${GW:-10.10.0.1}"
BRIDGE="${BRIDGE:-vmbr0}"

MEM_MB="${MEM_MB:-2048}"
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-32}"

STORAGE="${STORAGE:-local-lvm}"               # rootfs storage (lvmthin)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}" # 'dir' storage that has vztmpl content

SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

# Template selection (future-proof)
DIST="${DIST:-ubuntu}"
SERIES="${SERIES:-24.04}"
FLAVOR="${FLAVOR:-standard}"

# ---- Helpers ----
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need pct
need pveam
need awk
need grep
need sort
need sed

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  echo "ERROR: SSH public key not found at $SSH_PUBKEY_FILE" >&2
  exit 1
fi

# ---- Derive CTID from IP (last two octets -> concat) ----
IP="${IP_CIDR%%/*}"   # 10.10.100.10
O3="$(awk -F. '{print $3}' <<<"$IP")"
O4="$(awk -F. '{print $4}' <<<"$IP")"
CTID="${CTID:-${O3}${O4}}"  # e.g. 100 + 10 => "10010"

echo "==> Target: CTID=${CTID} CT_HOSTNAME=${CT_HOSTNAME} IP=${IP_CIDR} GW=${GW} BRIDGE=${BRIDGE}"

# ---- Resolve latest template ----
echo "==> Refresh template list"
pveam update >/dev/null

# Escape dots for regex (24.04 -> 24\.04)
SERIES_RE="$(sed 's/\./\\./g' <<<"$SERIES")"

echo "==> Resolving latest template for: ${DIST}-${SERIES}-${FLAVOR}"
AVAILABLE="$(pveam available -section system || true)"
if [[ -z "$AVAILABLE" ]]; then
  echo "ERROR: pveam available returned empty output. Is pveam working / network OK?" >&2
  exit 1
fi

TEMPLATE="$(
  printf "%s\n" "$AVAILABLE" \
  | awk '{print $2}' \
  | grep -E "^${DIST}-${SERIES_RE}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.zst$" \
  | sort -V \
  | tail -n 1
)"

if [[ -z "${TEMPLATE}" ]]; then
  echo "ERROR: Could not find matching template." >&2
  echo "Wanted regex:" >&2
  echo "  ^${DIST}-${SERIES_RE}-${FLAVOR}_[0-9]+\\.[0-9]+-[0-9]+_amd64\\.tar\\.zst$" >&2
  echo "Available ubuntu templates (debug):" >&2
  printf "%s\n" "$AVAILABLE" | grep -i ubuntu | head -n 30 >&2 || true
  exit 1
fi

echo "==> Latest template resolved: ${TEMPLATE}"

# ---- Ensure template cached ----
CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ -f "${CACHE}" ]]; then
  echo "==> Template already cached: ${CACHE}"
else
  echo "==> Downloading template to ${TEMPLATE_STORAGE}..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
fi

OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
echo "==> Using ostemplate: ${OSTEMPLATE}"

# ---- Create or update CT ----
if ! pct status "${CTID}" >/dev/null 2>&1; then
  echo "==> Creating CT ${CTID} (${CT_HOSTNAME} @ ${IP_CIDR})"
  pct create "${CTID}" "${OSTEMPLATE}" \
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
  pct set "${CTID}" \
    --hostname "${CT_HOSTNAME}" \
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
