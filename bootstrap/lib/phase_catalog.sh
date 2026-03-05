#!/usr/bin/env bash
set -euo pipefail

RALF_PHASE_SERVICES_FOUNDATION_CORE=(
  "010-minio"
  "020-postgresql"
  "030-gitea"
  "040-semaphore"
)

RALF_PHASE_SERVICES_FOUNDATION_SERVICES=(
  "050-vaultwarden"
  "060-prometheus"
)

RALF_PHASE_SERVICES_EXTENSION=(
  "070-n8n"
  "080-ki"
  "085-matrix"
)

RALF_PHASE_SERVICES_OPERATING_MODE=(
  "090-semaphore-first"
)
