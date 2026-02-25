#!/usr/bin/env bash
set -euo pipefail

# Compatibility adapter entrypoint. The implementation still lives under
# bootstrap/legacy/ while the new bootstrap CLI refers to adapters/*.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/legacy/start_proxmox_pct.sh" "$@"
