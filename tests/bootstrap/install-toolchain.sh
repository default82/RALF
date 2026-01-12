#!/usr/bin/env bash
set -euo pipefail

echo "== TOOLCHAIN INSTALL (idempotent) =="

# Basic tools
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl jq git unzip gnupg lsb-release

echo "OK: base tools installed"

# OpenTofu (binary install)
TOFU_VERSION="${TOFU_VERSION:-1.8.6}"
ARCH="$(dpkg --print-architecture)"   # amd64
OS="linux"

echo "Installing OpenTofu ${TOFU_VERSION} for ${OS}_${ARCH}"
curl -fsSL -o /tmp/tofu.zip "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_${OS}_${ARCH}.zip"
unzip -o /tmp/tofu.zip -d /usr/local/bin
chmod +x /usr/local/bin/tofu
rm -f /tmp/tofu.zip

echo "OK: tofu installed -> $(command -v tofu)"
tofu version

echo "== TOOLCHAIN OK =="
