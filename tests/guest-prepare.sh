#!/usr/bin/env bash

# shellcheck disable=SC2016

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_ROOT
readonly SCRIPT="${PROJECT_ROOT}/scripts/ralf-standalone-guest-prepare.sh"
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

prepare_environment() {
  local root=$1
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run"
  cat >"$root/etc/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="26.04"
NAME="Ubuntu"
PRETTY_NAME="Ubuntu 26.04 LTS"
EOF
}

prepare_stubs() {
  local directory=$1
  make_stub "$directory" id 'if [[ ${TEST_NON_ROOT:-0} == 1 && ${1:-} == -u ]]; then printf "1000\n"; elif [[ ${1:-} == -u ]]; then printf "0\n"; else exec /usr/bin/id "$@"; fi'
  make_stub "$directory" uname 'if [[ ${1:-} == -m ]]; then printf "%s\n" "${TEST_ARCH:-x86_64}"; else exec /usr/bin/uname "$@"; fi'
  make_stub "$directory" systemctl 'printf "systemctl %s\n" "$*" >> "$CALL_LOG"; case "$*" in "is-system-running") if [[ ${TEST_SYSTEMD_FAILURE:-0} == 1 ]]; then printf "degraded\n"; exit 1; else printf "running\n"; fi ;; "is-active systemd-networkd") if [[ ${TEST_NETWORK_FAILURE:-0} == 1 ]]; then printf "inactive\n"; exit 3; else printf "active\n"; fi ;; *--failed*) if [[ ${TEST_FAILED_UNITS:-0} == 1 ]]; then printf "broken.service loaded failed failed test\n"; fi ;; esac'
  make_stub "$directory" ip 'printf "ip %s\n" "$*" >> "$CALL_LOG"; case "$*" in "-4 -o addr show scope global") if [[ ${TEST_NETWORK_FAILURE:-0} != 1 ]]; then printf "2: eth0    inet 10.10.200.11/24 scope global eth0\n"; fi ;; "-4 route show default") if [[ ${TEST_NETWORK_FAILURE:-0} != 1 ]]; then printf "default via 10.10.0.1 dev eth0\n"; fi ;; esac'
  make_stub "$directory" getent 'printf "getent %s\n" "$*" >> "$CALL_LOG"; if [[ ${TEST_NETWORK_FAILURE:-0} == 1 ]]; then exit 2; fi; printf "10.10.200.1 STREAM archive.ubuntu.com\n"'
  make_stub "$directory" curl 'printf "curl %s\n" "$*" >> "$CALL_LOG"; if [[ ${TEST_SOURCE_FAILURE:-0} == 1 ]]; then exit 7; fi; printf "ok\n"'
  make_stub "$directory" dpkg 'printf "dpkg %s\n" "$*" >> "$CALL_LOG"; if [[ "$*" == "--audit" && ${TEST_BROKEN_DPKG:-0} == 1 ]]; then exit 1; fi; exit 0'
  make_stub "$directory" apt-get 'printf "apt-get %s\n" "$*" >> "$CALL_LOG"; case "$*" in *" update"|*" update ") if [[ ${TEST_APT_UPDATE_FAILURE:-0} == 1 ]]; then exit 10; fi ;; *full-upgrade*) if [[ ${TEST_PACKAGE_UPDATE_FAILURE:-0} == 1 ]]; then exit 11; fi ;; esac; exit 0'
  make_stub "$directory" install 'printf "install %s\n" "$*" >> "$CALL_LOG"; exec /usr/bin/install "$@"'
  make_stub "$directory" chmod 'printf "chmod %s\n" "$*" >> "$CALL_LOG"; exec /usr/bin/chmod "$@"'
  make_stub "$directory" chown 'printf "chown %s\n" "$*" >> "$CALL_LOG"; exec /usr/bin/chown "$@"'
}

run_script() {
  local root=$1
  local stub_dir=$2
  shift 2
  RALF_GUEST_ROOT="$root" CALL_LOG="${root}/calls.log" PATH="${stub_dir}:/usr/bin:/bin" \
    "$SCRIPT" "$@"
}

assert_no_mutation() {
  local log=$1
  if [[ -f $log ]] && grep -Eq 'apt-get|install |chmod |chown |reboot|shutdown|mkdir' "$log"; then
    printf 'FAIL: unerwartete Mutation im Log %s\n' "$log" >&2
    cat "$log" >&2
    return 1
  fi
}

assert_no_forbidden_installation() {
  local log=$1
  if [[ -f $log ]] && grep -Eiq '(^| )(ollama|qwen2\.5-coder|open-webui|docker|podman)( |$)|apt-get .*autoremove|do-release-upgrade' "$log"; then
    printf 'FAIL: verbotene Installation im Log %s\n' "$log" >&2
    cat "$log" >&2
    return 1
  fi
}

assert_directories() {
  local root=$1
  local directory metadata
  local -a directories=(
    "$root/etc/ralf"
    "$root/var/lib/ralf/ollama"
    "$root/var/lib/ralf/webui"
    "$root/var/log/ralf"
  )
  for directory in "${directories[@]}"; do
    [[ -d $directory && ! -L $directory ]] || { printf 'FAIL: Verzeichnis fehlt: %s\n' "$directory" >&2; return 1; }
    metadata=$(stat -c '%U:%G %a' "$directory")
    [[ $metadata == 'root:root 750' ]] || { printf 'FAIL: falsche Metadaten %s: %s\n' "$directory" "$metadata" >&2; return 1; }
  done
}

run_plan_case() {
  local case_dir="${TEST_ROOT}/plan"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  output=$(run_script "$root" "$stub_dir" --plan 2>&1)
  grep -Fq 'Plan erfolgreich; es werden keine Änderungen vorgenommen.' <<<"$output"
  grep -Fq 'apt-get update' <<<"$output"
  grep -Fq '/var/lib/ralf/ollama/' <<<"$output"
  grep -Fq 'root:root' <<<"$output"
  grep -Fq '0750' <<<"$output"
  grep -Fq 'kein automatischer Neustart' <<<"$output"
  grep -Fq 'Ollama' <<<"$output"
  assert_no_mutation "${root}/calls.log"
  [[ ! -e "$root/etc/ralf" ]] || { printf 'FAIL: Plan legte Verzeichnisse an\n' >&2; return 1; }
  printf 'PASS plan-no-mutation\n'
}

run_preflight_failure_case() {
  local name=$1
  local variable=$2
  local value=$3
  local expected=$4
  local case_dir="${TEST_ROOT}/${name}"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  local status
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  if [[ $name == wrong-os ]]; then sed -i 's/^ID=.*/ID=debian/' "$root/etc/os-release"; fi
  if [[ $name == wrong-version ]]; then sed -i 's/^VERSION_ID=.*/VERSION_ID="24.04"/' "$root/etc/os-release"; fi
  set +e
  output=$(env "$variable=$value" RALF_GUEST_ROOT="$root" CALL_LOG="${root}/calls.log" PATH="${stub_dir}:/usr/bin:/bin" "$SCRIPT" --apply 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] || { printf 'FAIL %s: Status %s\n%s\n' "$name" "$status" "$output" >&2; return 1; }
  grep -Fq "$expected" <<<"$output" || { printf 'FAIL %s: Ausgabe fehlt: %s\n%s\n' "$name" "$expected" "$output" >&2; return 1; }
  grep -Fq 'Preflight abgeschlossen: nein' <<<"$output"
  assert_no_mutation "${root}/calls.log"
  [[ ! -e "$root/etc/ralf" ]] || { printf 'FAIL %s: Mutation vor Preflight\n' "$name" >&2; return 1; }
  printf 'PASS %s\n' "$name"
}

run_dpkg_failure_case() {
  local case_dir="${TEST_ROOT}/broken-dpkg"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  local status
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  set +e
  output=$(TEST_BROKEN_DPKG=1 RALF_GUEST_ROOT="$root" CALL_LOG="${root}/calls.log" PATH="${stub_dir}:/usr/bin:/bin" "$SCRIPT" --apply 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] || { printf 'FAIL broken-dpkg: Status %s\n%s\n' "$status" "$output" >&2; return 1; }
  grep -Fq 'dpkg meldet' <<<"$output"
  assert_no_mutation "${root}/calls.log"
  printf 'PASS broken-dpkg\n'
}

run_apply_case() {
  local name=$1
  local case_dir="${TEST_ROOT}/${name}"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  output=$(run_script "$root" "$stub_dir" --apply 2>&1)
  grep -Fq 'Vorbereitung erfolgreich' <<<"$output"
  grep -Fq 'apt-get update: erfolgreich' <<<"$output"
  grep -Fq 'Paketaktualisierung: erfolgreich' <<<"$output"
  assert_directories "$root"
  assert_no_forbidden_installation "${root}/calls.log"
  grep -Fq 'apt-get -o Dpkg::Options::=--force-confold update' "${root}/calls.log"
  grep -Fq 'apt-get -o Dpkg::Options::=--force-confold -y full-upgrade' "${root}/calls.log"
  [[ $(grep -Ec '^install ' "${root}/calls.log") == 4 ]] || { printf 'FAIL %s: nicht exakt vier install-Aufrufe\n' "$name" >&2; return 1; }
  printf 'PASS %s\n' "$name"
}

run_apt_failure_case() {
  local name=$1
  local variable=$2
  local expected=$3
  local case_dir="${TEST_ROOT}/${name}"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  local status
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  set +e
  output=$(env "$variable=1" RALF_GUEST_ROOT="$root" CALL_LOG="${root}/calls.log" PATH="${stub_dir}:/usr/bin:/bin" "$SCRIPT" --apply 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] || { printf 'FAIL %s: Status %s\n%s\n' "$name" "$status" "$output" >&2; return 1; }
  grep -Fq "$expected" <<<"$output"
  grep -Fq 'Preflight abgeschlossen: ja' <<<"$output"
  grep -Fq 'Basisverzeichnisse: nicht begonnen' <<<"$output"
  [[ ! -e "$root/etc/ralf" ]] || { printf 'FAIL %s: Verzeichnisse trotz Paketfehler\n' "$name" >&2; return 1; }
  [[ $(grep -Ec '^install ' "${root}/calls.log" || true) == 0 ]] || { printf 'FAIL %s: install trotz Paketfehler\n' "$name" >&2; return 1; }
  printf 'PASS %s\n' "$name"
}

run_repeat_case() {
  local case_dir="${TEST_ROOT}/repeat"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  output=$(run_script "$root" "$stub_dir" --apply 2>&1)
  output+=$'\n'"$(run_script "$root" "$stub_dir" --apply 2>&1)"
  grep -Fq 'Vorbereitung erfolgreich' <<<"$output"
  assert_directories "$root"
  [[ $(grep -Ec '^apt-get .* update' "${root}/calls.log") == 2 ]] || { printf 'FAIL repeat: apt-get update nicht zweimal\n' >&2; return 1; }
  [[ $(grep -Ec 'full-upgrade' "${root}/calls.log") == 2 ]] || { printf 'FAIL repeat: full-upgrade nicht zweimal\n' >&2; return 1; }
  assert_no_forbidden_installation "${root}/calls.log"
  printf 'PASS repeat-idempotent\n'
}

run_reboot_required_case() {
  local case_dir="${TEST_ROOT}/reboot-required"
  local root="${case_dir}/root"
  local stub_dir="${case_dir}/bin"
  local output
  mkdir -p "$case_dir"
  prepare_environment "$root"
  prepare_stubs "$stub_dir"
  : >"$root/var/run/reboot-required"
  output=$(run_script "$root" "$stub_dir" --apply 2>&1)
  grep -Fq 'Neustart erforderlich: ja (nur gemeldet)' <<<"$output"
  if grep -Eiq '(^| )(reboot|shutdown|pct)( |$)' "${root}/calls.log"; then
    printf 'FAIL reboot-required: Neustart oder Hostmutation ausgeführt\n' >&2
    return 1
  fi
  printf 'PASS reboot-required-only-reported\n'
}

run_plan_case
run_preflight_failure_case non-root TEST_NON_ROOT 1 'root ausgeführt werden'
run_preflight_failure_case wrong-os TEST_NOOP 1 'Nicht unterstütztes Betriebssystem'
run_preflight_failure_case wrong-version TEST_NOOP 1 'Nicht unterstützte Ubuntu-Version'
run_preflight_failure_case missing-network TEST_NETWORK_FAILURE 1 'systemd-networkd'
run_dpkg_failure_case
run_apply_case successful
run_apt_failure_case apt-update-failure TEST_APT_UPDATE_FAILURE 'apt-get update ist fehlgeschlagen'
run_apt_failure_case package-update-failure TEST_PACKAGE_UPDATE_FAILURE 'apt-get full-upgrade ist fehlgeschlagen'
run_repeat_case
run_reboot_required_case
