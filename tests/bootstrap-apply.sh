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
  make_stub "$directory" pveam 'case "$1" in available) case "${TEST_CASE:-}" in missing-template) printf "system debian-13-standard_13.6-1_amd64.tar.zst\n" ;; *) printf "system ubuntu-26.04-standard_26.04-1_amd64.tar.zst\n" ;; esac ;; list) printf "NAME SIZE\nlocal:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst 151\n" ;; esac'
  make_stub "$directory" pvesh 'printf "pvesh %s\n" "$*" >> "$CALL_LOG"; case "$*" in */nextid*) printf "2200\n" ;; *) case "${TEST_CASE:-}" in occupied-vmid) printf "[{\"vmid\":2200}]\n" ;; *) printf "[]\n" ;; esac ;; esac'
  make_stub "$directory" pvesm 'case "$*" in *vztmpl*) printf "Name Type Status Total Used Available %%\nlocal dir active 1 0 1 0\n" ;; *) printf "Name Type Status Total Used Available %%\nlocal-lvm lvmthin active 1 0 1 0\n" ;; esac'
  make_stub "$directory" ip 'case "${TEST_CASE:-}" in multiple-bridge) printf "3: vmbr0: <UP>\n4: vmbr1: <UP>\n" ;; *) printf "3: vmbr0: <UP>\n" ;; esac'
  make_stub "$directory" pct 'printf "%s\n" "$*" >> "$PCT_LOG"; case "$1" in list) case "${TEST_CASE:-}" in existing-name) printf "VMID Status Lock Name\n2300 stopped - ralf-standalone\n" ;; *) printf "VMID Status Lock Name\n" ;; esac ;; config) [[ -e "$CREATED" ]] || exit 1; printf "unprivileged: 1\nhostname: ralf-standalone\ncores: %s\nmemory: %s\nswap: %s\nrootfs: %s:vm-2200-disk-0,size=%sG\nnet0: name=eth0,bridge=%s,ip=dhcp,type=veth\n" "$EXPECT_CORES" "$EXPECT_MEMORY" "$EXPECT_SWAP" "$EXPECT_STORAGE" "$EXPECT_DISK" "$EXPECT_BRIDGE" ;; status) [[ -e "$CREATED" ]] || exit 1; printf "status: stopped\n" ;; create) case "${TEST_CASE:-}" in create-failure) printf "mock pct create failed\n" >&2; exit 7 ;; *) touch "$CREATED"; printf "mock pct create succeeded\n" ;; esac ;; *) exit 1 ;; esac'
}

run_case() {
  local name=$1
  local expected_status=$2
  local expected_text=$3
  shift 3
  local stub_dir="${TEST_ROOT}/${name}"
  local pct_log="${stub_dir}/pct.log"
  local call_log="${stub_dir}/calls.log"
  local created="${stub_dir}/created"
  local output
  local status

  prepare_stubs "$stub_dir"
  set +e
  output=$(TEST_CASE="$name" PCT_LOG="$pct_log" CALL_LOG="$call_log" CREATED="$created" \
    EXPECT_CORES="${EXPECT_CORES:-4}" EXPECT_MEMORY="${EXPECT_MEMORY:-12288}" \
    EXPECT_SWAP="${EXPECT_SWAP:-4096}" EXPECT_STORAGE="${EXPECT_STORAGE:-local-lvm}" \
    EXPECT_DISK="${EXPECT_DISK:-40}" EXPECT_BRIDGE="${EXPECT_BRIDGE:-vmbr0}" \
    PATH="${stub_dir}:/usr/bin:/bin" "$SCRIPT" "$@" 2>&1)
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

  case "$name" in
    plan-no-create|check-no-create|occupied-vmid|existing-name|missing-template|invalid-storage|invalid-bridge|unknown-option)
      if [[ -f $pct_log ]] && grep -Eq '^create ' "$pct_log"; then
        printf 'FAIL %s: pct create wurde aufgerufen\n' "$name" >&2
        return 1
      fi
      ;;
    apply-success)
      [[ $(grep -Ec '^create ' "$pct_log") == 1 ]] || { printf 'FAIL %s: nicht genau ein pct create\n' "$name" >&2; return 1; }
      grep -Fq 'create 2200 local:vztmpl/ubuntu-26.04-standard' "$pct_log" || { printf 'FAIL %s: VMID/Template fehlen\n' "$name" >&2; return 1; }
      grep -Fq -- '--unprivileged 1 --cores 8 --memory 16384 --swap 8192 --rootfs local-lvm:60 --net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth' "$pct_log" || { printf 'FAIL %s: Ressourcenwerte fehlen\n' "$name" >&2; return 1; }
      ;;
    create-failure)
      [[ $(grep -Ec '^create ' "$pct_log") == 1 ]] || { printf 'FAIL %s: pct create nicht genau einmal aufgerufen\n' "$name" >&2; return 1; }
      ;;
  esac
}

run_case plan-no-create 0 'Plan erfolgreich' --plan
run_case check-no-create 0 'Plan erfolgreich' --check
EXPECT_CORES=8 EXPECT_MEMORY=16384 EXPECT_SWAP=8192 EXPECT_STORAGE=local-lvm EXPECT_DISK=60 EXPECT_BRIDGE=vmbr0 \
  run_case apply-success 0 'Container erstellt: ja' --apply --vmid 2200 --storage local-lvm --bridge vmbr0 --cores 8 --memory 16384 --swap 8192 --disk 60
run_case occupied-vmid 1 'bereits belegt' --apply --vmid 2200
run_case existing-name 1 'existiert bereits' --apply
run_case missing-template 1 'Kein Ubuntu-26.04-LXC-Template' --apply
run_case invalid-storage 1 'nicht als geeignete aktive Option' --apply --storage missing
run_case invalid-bridge 1 'nicht als geeignete aktive Option' --apply --bridge vmbr9
run_case create-failure 1 'Container erstellt: nein bestätigt' --apply
run_case unknown-option 1 'Unbekannte Option: --wat' --apply --wat
run_case conflicting-mode 1 'Widersprüchliche Ausführungsmodi' --plan --apply
