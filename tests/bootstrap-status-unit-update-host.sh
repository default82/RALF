#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_ROOT
readonly SCRIPT="$PROJECT_ROOT/scripts/ralf-bootstrap-status-unit-update.sh"
readonly TARGET_SHA='a26c500a7e4180f5fc9145b12ab05c3c7d6d598b0cad5d73bd7f7074fae85378'
readonly SOURCE_SHA='8f5b30c7d9335824dfabb19cab5b338337860a45e785a6985370da9b8f6f48d7'
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT

cleanup() {
  find "$TEST_ROOT" -type f -delete
  find "$TEST_ROOT" -depth -type d -empty -delete
}
trap cleanup EXIT

make_pct() {
  local bin=$1
  mkdir -p "$bin"
  cat >"$bin/pct" <<'SH'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%q ' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
case ${1:-} in
  status) printf 'status: running\n' ;;
  config) printf '%s\n' 'hostname: ralf-standalone' 'unprivileged: 1' 'features: nesting=1' ;;
  pending) printf '%s\n' 'cur hostname: ralf-standalone' ;;
  push)
    [[ ${TEST_PUSH_FAIL:-0} != 1 ]] || exit 1
    ;;
  exec)
    shift 3
    case ${1:-} in
      bash)
        if [[ ${2:-} == -s ]]; then
          printf '%s\n' "${TEST_CLASSIFIER_OUTPUT-RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_required}"
          [[ ${TEST_CLASSIFIER_STATUS:-0} == 0 ]]
        else
          [[ ${TEST_GUEST_FAIL:-0} != 1 ]]
        fi
        ;;
      sha256sum)
        if [[ ${TEST_CLASSIFIER_OUTPUT:-} == *unit_already_current* ]]; then
          printf '%s  %s\n' "$TEST_TARGET_SHA" /etc/systemd/system/ralf-bootstrap.service
        else
          printf '%s  %s\n' "$TEST_SOURCE_SHA" /etc/systemd/system/ralf-bootstrap.service
        fi
        ;;
      systemctl)
        printf '%s\n' 'ActiveState=active' 'SubState=running' 'Result=success' 'ExecMainStatus=0' 'NRestarts=0'
        ;;
      test) exit 1 ;;
      *) ;;
    esac
    ;;
esac
SH
  chmod 0755 "$bin/pct"
}

run_case() {
  local name=$1 mode=$2 classifier=$3 expected_status=$4
  local dir="$TEST_ROOT/$name" bin="$TEST_ROOT/$name/bin" log="$TEST_ROOT/$name/commands.log" output status
  mkdir -p "$dir"
  make_pct "$bin"
  set +e
  output=$(TEST_LOG="$log" TEST_TARGET_SHA="$TARGET_SHA" TEST_SOURCE_SHA="$SOURCE_SHA" \
    TEST_CLASSIFIER_OUTPUT="$classifier" PATH="$bin:/usr/bin:/bin" \
    "$SCRIPT" "--$mode" --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == "$expected_status" ]] || { printf '%s\n' "$output" >&2; return 1; }
  printf '%s\n' "$output" >"$dir/output"
}

run_case plan-required plan 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_required' 0
grep -Fq 'Klassifikation: unit_update_required' "$TEST_ROOT/plan-required/output"
if grep -Eq ' push |install -d|--apply| daemon-reload| restart ' "$TEST_ROOT/plan-required/commands.log"; then exit 1; fi
printf 'PASS host-plan-read-only\n'

run_case already-current apply 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_already_current' 0
grep -Fq 'keine Übertragung oder Mutation' "$TEST_ROOT/already-current/output"
if grep -Eq ' push |install -d|daemon-reload| restart ' "$TEST_ROOT/already-current/commands.log"; then exit 1; fi
printf 'PASS host-already-current-idempotent\n'

run_case conflict plan 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' 1
grep -Fq 'unit_update_conflict' "$TEST_ROOT/conflict/output"
printf 'PASS host-conflict-rejected\n'

for malformed in '' 'RALF_BOOTSTRAP_UNIT_STATE_V1=future_state' $'noise\nRALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_required'; do
  malformed_name=$(printf '%s' "$malformed" | sha256sum | cut -c1-8)
  run_case "malformed-$malformed_name" plan "$malformed" 1
done
printf 'PASS host-machine-output-strict\n'

run_case apply-required apply 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_required' 0
[[ $(grep -c '^push ' "$TEST_ROOT/apply-required/commands.log") == 3 ]]
[[ $(grep -c 'unit-update-guest.sh --apply' "$TEST_ROOT/apply-required/commands.log") == 1 ]]
if grep -Eq 'runtime\.lock|\.whl|config\.toml' "$TEST_ROOT/apply-required/commands.log"; then exit 1; fi
grep -Fq 'rm -f -- /run/ralf-bootstrap-unit-update/ralf-bootstrap.service' "$TEST_ROOT/apply-required/commands.log"
printf 'PASS host-apply-three-files-once\n'

dir="$TEST_ROOT/apply-failure"; bin="$dir/bin"; log="$dir/commands.log"; mkdir -p "$dir"; make_pct "$bin"
set +e
TEST_LOG="$log" TEST_TARGET_SHA="$TARGET_SHA" TEST_SOURCE_SHA="$SOURCE_SHA" TEST_GUEST_FAIL=1 \
  PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --vmid 100 >"$dir/output" 2>&1
status=$?
set -e
[[ $status == 1 ]]
[[ $(grep -c 'unit-update-guest.sh --apply' "$log") == 1 ]]
if grep -Fq 'rm -f -- /run/ralf-bootstrap-unit-update' "$log"; then exit 1; fi
printf 'PASS host-failure-no-retry-no-cleanup\n'

grep -Fq 'bash -s -- --classify --target-sha256' "$SCRIPT"
if grep -Eq 'ralf_bootstrap-.*\.whl|runtime\.lock|config\.toml' "$SCRIPT"; then exit 1; fi
grep -Fq 'for file in ralf-bootstrap.service ralf-bootstrap-status-unit-update-guest.sh SHA256SUMS' "$SCRIPT"
printf 'PASS host-single-guest-classifier-and-bundle-scope\n'
