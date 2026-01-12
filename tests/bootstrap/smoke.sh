#!/usr/bin/env bash
set -euo pipefail

echo "BOOTSTRAP SMOKE: repo is checked out and scripts can run."
echo "Timestamp: $(date -Is)"
echo "User: $(id -un)"
echo "PWD: $(pwd)"

# Tools that must exist for the bootstrap stage
for t in git bash; do
  command -v "$t" >/dev/null 2>&1 || { echo "Missing tool: $t"; exit 1; }
  echo "OK: $t -> $(command -v "$t")"
done

echo "SMOKE OK"
