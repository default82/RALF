#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# Creates/starts LXC bootstrap container idempotent-ish.
# Runs on the Proxmox host (pve-deploy).

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
need head
need tail
need printf

die() { echo "ERROR: $*" >&2; exit 1; }

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  die "SSH public key not found at $SSH_PUBKEY_FILE"
fi

# ---- Derive CTID from IP (last two octets -> concat) ----
IP="${IP_CIDR%%/*}"   # 10.10.100.10
O3="$(awk -F. '{print $3}' <<<"$IP")"
O4="$(awk -F. '{print $4}' <<<"$IP")"
CTID="${CTID:-${O3}${O4}}"  # e.g. 100 + 10 => "10010"

echo "==> Target: CTID=${CTID} CT_HOSTNAME=${CT_HOSTNAME} IP=${IP_CIDR} GW=${GW} BRIDGE=${BRIDGE}"
echo "==> Storage: rootfs=${STORAGE} templates=${TEMPLATE_STORAGE}"

# ---- Resolve latest template (future-proof) ----
echo "==> Refresh template list"
pveam update >/dev/null

echo "==> Resolving latest template for: ${DIST}-${SERIES}-${FLAVOR}"
CANDIDATES="$(
  pveam available -section system \
    | awk '{print $NF}' \
    | grep -E "^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.(xz|zst)$" \
    || true
)"

if [[ -z "$CANDIDATES" ]]; then
  echo "ERROR: No matching template found for ${DIST}-${SERIES}-${FLAVOR}" >&2
  echo "Available ${DIST} templates (first 20):" >&2
  pveam available -section system | awk '{print $NF}' | grep -i "^${DIST}" | head -n 20 >&2
  exit 1
fi

TEMPLATE="$(printf "%s\n" "$CANDIDATES" | sort -V | tail -n 1)"
echo "==> Latest template resolved: ${TEMPLATE}"

# ---- Ensure template is cached ----
CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ -f "$CACHE" ]]; then
  echo "==> Template already cached: ${CACHE}"
else
  echo "==> Downloading template to ${TEMPLATE_STORAGE}..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
fi

OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
echo "==> Using ostemplate: ${OSTEMPLATE}"

# ---- Determine if pct supports SSH pubkeys option on create/set ----
PCT_CREATE_HELP="$(pct create --help 2>/dev/null || true)"
PCT_SET_HELP="$(pct set --help 2>/dev/null || true)"

SUPPORTS_CREATE_SSH_KEYS=0
SUPPORTS_SET_SSH_KEYS=0
grep -q -- '--ssh-public-keys' <<<"$PCT_CREATE_HELP" && SUPPORTS_CREATE_SSH_KEYS=1
grep -q -- '--ssh-public-keys' <<<"$PCT_SET_HELP" && SUPPORTS_SET_SSH_KEYS=1

# ---- Create or update CT ----
CREATED=0
if ! pct status "${CTID}" >/dev/null 2>&1; then
  echo "==> Creating CT ${CTID} (${CT_HOSTNAME} @ ${IP_CIDR})"

  CREATE_ARGS=(
    "${CTID}" "${OSTEMPLATE}"
    --hostname "${CT_HOSTNAME}"
    --memory "${MEM_MB}"
    --cores "${CORES}"
    --rootfs "${STORAGE}:${DISK_GB}"
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}"
    --unprivileged 1
    --features "nesting=1"
    --start 0
  )

  if [[ $SUPPORTS_CREATE_SSH_KEYS -eq 1 ]]; then
    echo "==> pct create supports --ssh-public-keys (using it)"
    CREATE_ARGS+=( --ssh-public-keys "${SSH_PUBKEY_FILE}" )
  else
    echo "==> pct create does NOT support --ssh-public-keys (will inject via pct exec)"
  fi

  pct create "${CREATE_ARGS[@]}"
  CREATED=1
else
  echo "==> CT ${CTID} already exists. Ensuring config is set."
  # NOTE: create-time only options like --unprivileged must NOT be set here.
  pct set "${CTID}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --features "nesting=1" >/dev/null

  # If supported, we can also set ssh keys here; otherwise fallback later.
  if [[ $SUPPORTS_SET_SSH_KEYS -eq 1 ]]; then
    echo "==> pct set supports --ssh-public-keys (using it)"
    pct set "${CTID}" --ssh-public-keys "${SSH_PUBKEY_FILE}" >/dev/null
  else
    echo "==> pct set does NOT support --ssh-public-keys (will inject via pct exec)"
  fi
fi

echo "==> Starting CT ${CTID}"
pct start "${CTID}" >/dev/null 2>&1 || true

# ---- Fallback: inject SSH pubkey via pct exec if pct can't do it ----
if [[ $SUPPORTS_CREATE_SSH_KEYS -eq 0 && $SUPPORTS_SET_SSH_KEYS -eq 0 ]]; then
  echo "==> Injecting SSH pubkey via pct exec into /root/.ssh/authorized_keys"
  PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
  pct exec "${CTID}" -- bash -lc "
    set -euo pipefail
    install -d -m 0700 /root/.ssh
    touch /root/.ssh/authorized_keys
    chmod 0600 /root/.ssh/authorized_keys
    grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys
  "
fi

echo "==> Status:"
pct status "${CTID}"

echo "==> Done."
echo "   Next: pct exec ${CTID} -- bash -lc 'hostname; ip -br a; uname -a'"
