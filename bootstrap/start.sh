#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# Runs on Proxmox host. Creates/starts the Bootstrap LXC and installs toolchain inside.
# Bootstrap container is intended to become the later Semaphore container.

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

# Toolchain versions (pin if you want; "latest" behavior is implemented for terragrunt)
TERRAGRUNT_VERSION="${TERRAGRUNT_VERSION:-latest}"

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
need sed
need curl

# ---- Tiny progress UI ----
STEP_N=0
step() { STEP_N=$((STEP_N+1)); echo; echo "[STEP ${STEP_N}] $*"; }
ok() { echo "✔ $*"; }
warn() { echo "⚠ $*" >&2; }
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

# ---- Resolve latest template ----
step "Resolving Proxmox LXC template (${DIST}-${SERIES}-${FLAVOR})"
pveam update >/dev/null

CANDIDATES="$(
  pveam available -section system \
    | awk '{print $NF}' \
    | grep -E "^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.(xz|zst)$" \
    || true
)"

if [[ -z "$CANDIDATES" ]]; then
  echo "Available ${DIST} templates (first 30):" >&2
  pveam available -section system | awk '{print $NF}' | grep -i "^${DIST}" | head -n 30 >&2
  die "No matching template found for ${DIST}-${SERIES}-${FLAVOR}"
fi

TEMPLATE="$(printf "%s\n" "$CANDIDATES" | sort -V | tail -n 1)"
ok "Template: ${TEMPLATE}"

# ---- Ensure template cached ----
CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ -f "$CACHE" ]]; then
  ok "Template cached: ${CACHE}"
else
  step "Downloading template to ${TEMPLATE_STORAGE}"
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
  ok "Template downloaded"
fi

OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
ok "Using ostemplate: ${OSTEMPLATE}"

# ---- Create or update CT ----
CT_EXISTS=0
if pct status "${CTID}" >/dev/null 2>&1; then
  CT_EXISTS=1
fi

CT_RUNNING=0
if [[ "$CT_EXISTS" -eq 1 ]]; then
  if pct status "${CTID}" 2>/dev/null | grep -q "running"; then
    CT_RUNNING=1
  fi
fi

step "Creating/updating container ${CTID}"
if [[ "$CT_EXISTS" -eq 0 ]]; then
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
  # Only update safe, non-readonly options.
  # Avoid setting net0 while running to prevent "Address already assigned".
  if [[ "$CT_RUNNING" -eq 1 ]]; then
    warn "CT is running; will NOT live-change net0 to avoid 'Address already assigned'."
    pct set "${CTID}" \
      --hostname "${CT_HOSTNAME}" \
      --memory "${MEM_MB}" \
      --cores "${CORES}" \
      --features "nesting=1" >/dev/null
  else
    pct set "${CTID}" \
      --hostname "${CT_HOSTNAME}" \
      --memory "${MEM_MB}" \
      --cores "${CORES}" \
      --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
      --features "nesting=1" >/dev/null
  fi
  ok "Container updated"
fi

# ---- Start CT ----
step "Starting container"
pct start "${CTID}" >/dev/null 2>&1 || true
pct status "${CTID}" | grep -q "running" || die "Container did not start"
ok "Container running"

# ---- Inject SSH key (since pct set --ssh-public-keys may not exist) ----
step "Injecting SSH pubkey into /root/.ssh/authorized_keys"
PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
pct exec "${CTID}" -- bash -lc "set -euo pipefail
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys
"
ok "SSH key ready"

# ---- Install toolchain inside CT ----
step "Installing base packages + toolchain (ansible/opentofu/terragrunt)"
pct exec "${CTID}" -- bash -lc "set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release unzip jq git openssh-server \
  python3 python3-venv python3-pip \
  software-properties-common

# Ansible (good enough for bootstrap; can be pinned later)
apt-get install -y ansible

# OpenTofu via official installer (standalone)
# Ref: https://opentofu.org/docs/intro/install/standalone/
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
chmod +x /tmp/install-opentofu.sh
/tmp/install-opentofu.sh --install-method standalone --skip-verify
rm -f /tmp/install-opentofu.sh

# Terragrunt
ARCH=\$(dpkg --print-architecture)
case \"\$ARCH\" in
  amd64) TG_ARCH=amd64 ;;
  arm64) TG_ARCH=arm64 ;;
  *) echo \"Unsupported arch: \$ARCH\" >&2; exit 1 ;;
esac

if [[ \"${TERRAGRUNT_VERSION}\" = \"latest\" ]]; then
  # GitHub API (simple) – robust enough for bootstrap
  TG_VER=\$(curl -fsSL https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | jq -r .tag_name)
else
  TG_VER=\"${TERRAGRUNT_VERSION}\"
fi

curl -fsSL -o /usr/local/bin/terragrunt \"https://github.com/gruntwork-io/terragrunt/releases/download/\${TG_VER}/terragrunt_linux_\${TG_ARCH}\"
chmod 0755 /usr/local/bin/terragrunt

# sanity
command -v ansible >/dev/null
command -v tofu >/dev/null
command -v terragrunt >/dev/null
"
ok "Toolchain installed"

step "Show versions"
pct exec "${CTID}" -- bash -lc "set -euo pipefail
echo 'ansible:'; ansible --version | head -n 1
echo 'tofu:'; tofu version | head -n 1
echo 'terragrunt:'; terragrunt --version | head -n 1
"
ok "Bootstrap container ready"

echo
echo "==> Done."
echo "   CTID: ${CTID}"
echo "   Login: ssh root@${IP}  (key from ${SSH_PUBKEY_FILE})"
echo "   Next:  pct exec ${CTID} -- bash -lc 'hostname; ip -br a; uname -a'"
