#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# Creates/starts LXC bootstrap container idempotent-ish.
# Runs on the Proxmox host (pve-deploy).
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh | bash
#
# Optional overrides (examples):
#   CT_HOSTNAME=ralf-bootstrap IP_CIDR=10.10.100.10/16 MEM_MB=2048 DISK_GB=32 CORES=1 bash start.sh
#   DIST=ubuntu SERIES=24.04 FLAVOR=standard bash start.sh

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

# ---- Progress helpers (simple, no deps) ----
step() { echo; echo "[STEP $1] $2"; }
ok()   { echo "✔ $1"; }
warn() { echo "⚠ $1" >&2; }
die()  { echo "ERROR: $1" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

need pct
need pveam
need awk
need grep
need sort
need head
need tail
need printf
need sed
need ip

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  die "SSH public key not found at $SSH_PUBKEY_FILE"
fi

# ---- Derive CTID from IP (last two octets -> concat) ----
IP="${IP_CIDR%%/*}"   # 10.10.100.10
O3="$(awk -F. '{print $3}' <<<"$IP")"
O4="$(awk -F. '{print $4}' <<<"$IP")"
CTID="${CTID:-${O3}${O4}}"  # e.g. 100 + 10 => "10010" (string concat)

# ---- Basic sanity ----
[[ "$O3" =~ ^[0-9]+$ ]] || die "IP third octet is not numeric: $O3"
[[ "$O4" =~ ^[0-9]+$ ]] || die "IP fourth octet is not numeric: $O4"
(( O3 >= 0 && O3 <= 255 )) || die "IP third octet out of range: $O3"
(( O4 >= 0 && O4 <= 255 )) || die "IP fourth octet out of range: $O4"

echo "==> Target: CTID=${CTID} CT_HOSTNAME=${CT_HOSTNAME} IP=${IP_CIDR} GW=${GW} BRIDGE=${BRIDGE}"
echo "==> Storage: rootfs=${STORAGE} templates=${TEMPLATE_STORAGE}"

# ---- Resolve latest template (future-proof) ----
step 1 "Resolving template"
pveam update >/dev/null

CANDIDATES="$(
  pveam available -section system \
    | awk '{print $NF}' \
    | grep -E "^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.(xz|zst)$" \
    || true
)"

if [[ -z "$CANDIDATES" ]]; then
  warn "No matching template found for ${DIST}-${SERIES}-${FLAVOR}"
  warn "Available ${DIST} templates (first 30):"
  pveam available -section system | awk '{print $NF}' | grep -i "^${DIST}" | head -n 30 >&2 || true
  exit 1
fi

TEMPLATE="$(printf "%s\n" "$CANDIDATES" | sort -V | tail -n 1)"
ok "Template: ${TEMPLATE}"

CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ -f "$CACHE" ]]; then
  ok "Template cached"
else
  echo "Downloading template to ${TEMPLATE_STORAGE}..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
  ok "Template downloaded"
fi

OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

# ---- Create or update CT ----
if ! pct status "${CTID}" >/dev/null 2>&1; then
  step 2 "Creating container ${CTID}"

  pct create "${CTID}" "${OSTEMPLATE}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features "nesting=1" \
    --start 0

  ok "Container created"
else
  step 2 "Container exists — adjusting mutable settings"

  # NOTE: unprivileged is read-only once created; do not touch it here.
  pct set "${CTID}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --features "nesting=1" >/dev/null

  # net0 changes can be tricky while running; only set if config differs.
  CURRENT_NET0="$(pct config "${CTID}" | awk -F': ' '$1=="net0"{print $2}')"
  DESIRED_NET0="name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}"
  if [[ "${CURRENT_NET0}" != "${DESIRED_NET0}" ]]; then
    if pct status "${CTID}" 2>/dev/null | grep -q "running"; then
      warn "CT is running; not changing net0 live (avoids 'Address already assigned')."
      warn "If you changed IP/bridge, stop CT first and rerun, or destroy+recreate."
    else
      pct set "${CTID}" --net0 "${DESIRED_NET0}" >/dev/null
    fi
  fi

  ok "Config ensured"
fi

# ---- Start CT ----
step 3 "Starting container"
pct start "${CTID}" >/dev/null 2>&1 || true
pct status "${CTID}" | grep -q "running" && ok "Container running" || die "Container not running"

# ---- Inject SSH key (pct has no --ssh-public-keys on your version) ----
step 4 "Injecting SSH key"
PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
pct exec "${CTID}" -- bash -lc "set -euo pipefail
install -d -m 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys
"
ok "SSH key ready"

# ---- Install base toolchain inside CT ----
step 5 "Installing toolchain inside container"
pct exec "${CTID}" -- bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl unzip jq git openssh-server \
  python3 python3-venv python3-pip \
  ansible

# ---- OpenTofu (standalone, avoids apt+gpg issues) ----
if ! command -v tofu >/dev/null 2>&1; then
  curl --proto "=https" --tlsv1.2 -fsSL \
    https://get.opentofu.org/install-opentofu.sh \
    -o /tmp/install-opentofu.sh
  chmod +x /tmp/install-opentofu.sh
  /tmp/install-opentofu.sh --install-method standalone --skip-verify
  rm -f /tmp/install-opentofu.sh
fi

# ---- Terragrunt ----
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) TG_ARCH=amd64 ;;
  arm64) TG_ARCH=arm64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

if ! command -v terragrunt >/dev/null 2>&1; then
  TG_VER=$(curl -fsSL https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | jq -r .tag_name)
  curl -fsSL -o /usr/local/bin/terragrunt \
    "https://github.com/gruntwork-io/terragrunt/releases/download/${TG_VER}/terragrunt_linux_${TG_ARCH}"
  chmod 0755 /usr/local/bin/terragrunt
fi

# sanity
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

command -v tofu >/dev/null
command -v terragrunt >/dev/null
command -v ansible >/dev/null
'
ok "Toolchain installed"

echo
ok "Done."
echo "Next checks:"
echo "  pct exec ${CTID} -- bash -lc 'hostname; ip -br a; uname -a'"
echo "  pct exec ${CTID} -- bash -lc 'tofu version; terragrunt --version; ansible --version'"
