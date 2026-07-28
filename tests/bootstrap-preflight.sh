#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_ROOT
readonly SCRIPT="${PROJECT_ROOT}/scripts/ralf-standalone-bootstrap.sh"
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT
trap 'rm -rf -- "$TEST_ROOT"' EXIT

make_stub() {
  local directory=$1
  local name=$2
  local body=$3

  mkdir -p "$directory"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -Eeuo pipefail\n'
    printf '%s\n' "$body"
  } >"${directory}/${name}"
  chmod +x "${directory}/${name}"
}

run_case() {
  local name=$1
  local expected_status=$2
  local expected_text=$3
  local stub_dir="${TEST_ROOT}/${name}"
  local output
  local status

  make_stub "$stub_dir" pveversion 'printf "pve-manager/9.2.4\\n"'
  make_stub "$stub_dir" pveam 'printf "system local:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst\\n"'
  make_stub "$stub_dir" pct 'printf "VMID Status Lock Name\\n"'

  case "$name" in
    missing-template)
      make_stub "$stub_dir" pveam 'printf "system local:vztmpl/debian-13-standard_13.0-1_amd64.tar.zst\\n"'
      ;;
    existing-container)
      make_stub "$stub_dir" pct 'printf "VMID Status Lock Name\\n2200 stopped - ralf-standalone\\n"'
      ;;
  esac

  set +e
  output=$(PATH="${stub_dir}:/usr/bin:/bin" "$SCRIPT" --check 2>&1)
  status=$?
  set -e

  [[ $status == "$expected_status" ]] ||
    printf 'FAIL %s: Status %s statt %s\n%s\n' "$name" "$status" "$expected_status" "$output" >&2
  [[ $status == "$expected_status" ]] || return 1

  grep -Fq "$expected_text" <<<"$output" ||
    printf 'FAIL %s: Ausgabe enthält nicht: %s\n%s\n' "$name" "$expected_text" "$output" >&2
  grep -Fq "$expected_text" <<<"$output" || return 1

  printf 'PASS %s\n' "$name"
}

run_case success 0 'Preflight erfolgreich'
run_case missing-template 1 'Kein Ubuntu-26.04-LXC-Template'
run_case existing-container 1 'existiert bereits'
