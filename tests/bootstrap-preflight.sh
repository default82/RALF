#!/usr/bin/env bash

# shellcheck disable=SC2016

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

prepare_stubs() {
  local directory=$1
  make_stub "$directory" pveversion 'printf "pve-manager/9.2.4\n"'
  make_stub "$directory" pveam 'case "$1" in available) printf "system ubuntu-26.04-standard_26.04-1_amd64.tar.zst\n" ;; list) printf "NAME SIZE\nlocal:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst 151\n" ;; esac'
  make_stub "$directory" pvesh 'case "$*" in */nextid*) printf "2200\n" ;; *) case "${TEST_CASE:-}" in occupied-vmid) printf "[{\"vmid\":2200}]\n" ;; *) printf "[]\n" ;; esac ;; esac'
  make_stub "$directory" pvesm 'case "$*" in *vztmpl*) printf "Name Type Status Total Used Available %%\nlocal dir active 1 0 1 0\n" ;; *) case "${TEST_CASE:-}" in multiple-storage) printf "Name Type Status Total Used Available %%\nlocal dir active 1 0 1 0\nlocal-lvm lvmthin active 1 0 1 0\n" ;; *) printf "Name Type Status Total Used Available %%\nlocal-lvm lvmthin active 1 0 1 0\n" ;; esac ;; esac'
  make_stub "$directory" pct 'exit 0'
  make_stub "$directory" ip 'case "${TEST_CASE:-}" in multiple-bridge) printf "3: vmbr0: <UP>\n4: vmbr1: <UP>\n" ;; *) printf "3: vmbr0: <UP>\n" ;; esac'
}

run_case() {
  local name=$1
  local expected_status=$2
  local expected_text=$3
  shift 3
  local stub_dir="${TEST_ROOT}/${name}"
  local output
  local status

  prepare_stubs "$stub_dir"
  set +e
  output=$(TEST_CASE="$name" PATH="${stub_dir}:/usr/bin:/bin" "$SCRIPT" --plan "$@" 2>&1)
  status=$?
  set -e

  [[ $status == "$expected_status" ]] || {
    printf 'FAIL %s: Status %s statt %s\n%s\n' "$name" "$status" "$expected_status" "$output" >&2
    return 1
  }
  grep -Fq "$expected_text" <<<"$output" || {
    printf 'FAIL %s: Ausgabe enthält nicht: %s\n%s\n' "$name" "$expected_text" "$output" >&2
    return 1
  }
  printf 'PASS %s\n' "$name"
}

run_case valid-defaults 0 'RAM: 12288 MiB'
run_case valid-overrides 0 'CPU: 8 Kerne' --vmid 2300 --storage local-lvm --bridge vmbr0 --cores 8 --memory 16384 --swap 8192 --disk 60
run_case occupied-vmid 1 'bereits belegt'
run_case multiple-storage 1 'Mehrere geeignete Storage'
run_case multiple-bridge 1 'Mehrere geeignete Bridge'
run_case invalid-memory 1 'Ungültiger Wert für --memory' --memory nope
run_case unknown-option 1 'Unbekannte Option: --wat' --wat
run_case missing-value 1 'Fehlender Wert für --cores' --cores
