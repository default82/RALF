#!/usr/bin/env bash
set -euo pipefail

echo "TOOLCHAIN CHECK"
for t in git bash curl jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing tool: $t"; exit 1; }
  echo "OK: $t -> $(command -v "$t")"
done

# OpenTofu/Ansible kommen als nächster Schritt
# (noch nicht zwingend in diesem Checkpoint)
echo "TOOLCHAIN OK"
