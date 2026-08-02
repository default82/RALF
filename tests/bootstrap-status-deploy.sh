#!/usr/bin/env bash

# shellcheck disable=SC2016

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly SCRIPT="$PROJECT_ROOT/scripts/ralf-bootstrap-status-deploy.sh"
TEST_ROOT=$(mktemp -d)
trap 'find "$TEST_ROOT" -type f -delete; find "$TEST_ROOT" -depth -type d -empty -delete' EXIT

make_pct() {
  local dir=$1
  mkdir -p "$dir"
  cat >"$dir/pct" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"$PCT_LOG"
if [[ $1 == status ]]; then
  printf 'status: running\n'
elif [[ $1 == config ]]; then
  printf 'hostname: ralf-standalone\n'
elif [[ $1 == pending ]]; then
  printf 'cur hostname: ralf-standalone\n'
elif [[ $1 == exec ]]; then
  shift 3
  if [[ ${1:-} == python3 && ${2:-} == --version ]]; then
    printf 'Python 3.14.4\n'
  elif [[ ${1:-} == python3 && ${2:-} == -m ]]; then
    printf 'usage: venv\n'
  elif [[ ${1:-} == python3 && ${2:-} == -c ]]; then
    if [[ ${TEST_RESUME_STATE:-0} == 1 && ${3:-} == *'/run/ralf-bootstrap-install'* ]] || [[ ${TEST_REPAIR_STATE:-0} == 1 && ${3:-} == *'/run/ralf-bootstrap-install'* ]] || [[ ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 && ${3:-} == *'/run/ralf-bootstrap-install'* ]]; then
      printf 'valid\n'
    elif [[ ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 ]]; then
      printf 'recoverable_venv_repair_validation_failure\n'
    elif [[ ${TEST_REPAIR_STATE:-0} == 1 ]]; then
      printf 'recoverable_moved_venv_exec_failure\n'
    elif [[ ${TEST_RESUME_STATE:-0} == 1 ]]; then
      printf 'recoverable_venv_failure\n'
    else
      printf 'absent\n'
    fi
  elif [[ ${1:-} == test && ${2:-} == -d && ${3:-} == /run/ralf-bootstrap-install ]]; then
    [[ ${TEST_RESUME_STATE:-0} == 1 || ${TEST_REPAIR_STATE:-0} == 1 || ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 ]] || exit 1
  elif [[ ${1:-} == test ]]; then
    exit 1
  elif [[ ${1:-} == getent ]]; then
    exit 2
  elif [[ ${1:-} == sha256sum ]]; then
    :
  elif [[ ${1:-} == bash ]]; then
    if [[ $* == *'--classify --bundle'* ]]; then
      if [[ -n ${TEST_CLASSIFY_DIAGNOSTIC:-} ]]; then printf '%s\n' "$TEST_CLASSIFY_DIAGNOSTIC" >&2; fi
      if [[ ${TEST_CLASSIFY_OUTPUT+x} == x ]]; then
        printf '%b' "$TEST_CLASSIFY_OUTPUT"
      elif [[ ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 ]]; then
        printf 'RALF_BOOTSTRAP_STATE_V1=recoverable_venv_repair_validation_failure\n'
      elif [[ ${TEST_REPAIR_STATE:-0} == 1 ]]; then
        printf 'RALF_BOOTSTRAP_STATE_V1=recoverable_moved_venv_exec_failure\n'
      elif [[ ${TEST_RESUME_STATE:-0} == 1 ]]; then
        printf 'RALF_BOOTSTRAP_STATE_V1=recoverable_venv_failure\n'
      else
        printf 'RALF_BOOTSTRAP_STATE_V1=partial\n'
      fi
    elif [[ ${TEST_GUEST_FAILURE:-0} == 1 ]]; then exit 17
    fi
  elif [[ ${1:-} == rm ]]; then
    :
  elif [[ ${1:-} == install ]]; then
    :
  else
    exit 2
  fi
elif [[ $1 == push ]]; then
  :
else
  exit 2
fi
EOF
  chmod +x "$dir/pct"
}

run_case() {
  local name=$1
  local dir="$TEST_ROOT/$name" bin="$TEST_ROOT/$name/bin" build="$TEST_ROOT/$name/build" output status
  mkdir -p "$bin" "$build"
  make_pct "$bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exec /tmp/ralf-m029-uT3CBz/venv/bin/python "$@"' >"$build/python"
  chmod +x "$build/python"
  set +e
  output=$(TEST_GUEST_FAILURE="$([[ $name == failure ]] && printf 1 || printf 0)" RALF_BUILD_PYTHON="$build/python" PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" "--$([[ $name == plan ]] && printf plan || printf apply)" --vmid 100 2>&1)
  status=$?
  set -e
  if [[ $name == plan ]]; then
    [[ $status == 0 ]] && grep -Fq 'Plan erfolgreich' <<<"$output"
    if grep -q '^push ' "$dir/pct.log"; then return 1; fi
    printf 'PASS plan-no-transfer\n'
  elif [[ $name == failure ]]; then
    [[ $status == 1 ]] && [[ $(grep -c 'ralf-bootstrap-status-install.sh --apply' "$dir/pct.log") == 1 ]]
  if grep -q 'rm -rf /run/ralf-bootstrap-install' "$dir/pct.log"; then return 1; fi
    printf 'PASS apply-failure-no-retry\n'
  else
    [[ $status == 0 ]] && grep -Fq 'Deployment erfolgreich' <<<"$output"
    [[ $(grep -c '^push ' "$dir/pct.log") == 6 ]]
    printf 'PASS apply-exact-bundle\n'
  fi
}

run_resume_case() {
  local name=$1 mode
  local dir="$TEST_ROOT/$name" bin="$TEST_ROOT/$name/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  if [[ $name == resume-apply || $name == resume-failure ]]; then
    mode=--apply
  else
    mode=--plan
  fi
  set +e
  output=$(TEST_RESUME_STATE=1 TEST_GUEST_FAILURE="$([[ $name == resume-failure ]] && printf 1 || printf 0)" PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --resume "$mode" --vmid 100 2>&1)
  status=$?
  set -e
  if [[ $name == resume-plan ]]; then
    [[ $status == 0 ]] && grep -Fq 'Resume-Plan erfolgreich' <<<"$output"
    if grep -q '^push ' "$dir/pct.log"; then return 1; fi
    [[ $(grep -c -- '--resume --plan' "$dir/pct.log") == 1 ]]
    printf 'PASS resume-plan-no-transfer\n'
  elif [[ $name == resume-failure ]]; then
    [[ $status == 1 ]] && [[ $(grep -c -- '--resume --apply' "$dir/pct.log") == 1 ]]
    if grep -q 'rm -rf -- /run/ralf-bootstrap-install' "$dir/pct.log"; then return 1; fi
    printf 'PASS resume-failure-no-retry\n'
  else
    [[ $status == 0 ]] && grep -Fq 'Resume erfolgreich' <<<"$output"
    if grep -q '^push ' "$dir/pct.log"; then return 1; fi
    [[ $(grep -c -- '--resume --apply' "$dir/pct.log") == 1 ]]
    printf 'PASS resume-apply-no-transfer\n'
  fi
}

run_normal_apply_rejects_resume() {
  local dir="$TEST_ROOT/normal-resume-reject" bin="$TEST_ROOT/normal-resume-reject/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  set +e
  output=$(TEST_RESUME_STATE=1 PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'normaler --apply' <<<"$output"
  if grep -q '^push ' "$dir/pct.log"; then return 1; fi
  printf 'PASS normal-apply-resume-rejection\n'
}

run_repair_case() {
  local name=$1 mode output status
  local dir="$TEST_ROOT/$name" bin="$TEST_ROOT/$name/bin"
  mkdir -p "$bin"
  make_pct "$bin"
  [[ $name == repair-apply || $name == repair-failure ]] && mode=--apply || mode=--plan
  set +e
  output=$(TEST_REPAIR_STATE=1 TEST_GUEST_FAILURE="$([[ $name == repair-failure ]] && printf 1 || printf 0)" PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv "$mode" --vmid 100 2>&1)
  status=$?
  set -e
  if [[ $name == repair-plan ]]; then
    [[ $status == 0 ]] && grep -Fq 'Venv-Reparaturplan erfolgreich' <<<"$output"
    if grep -q '^push ' "$dir/pct.log"; then return 1; fi
    [[ $(grep -c -- '--repair-venv --plan' "$dir/pct.log") == 1 ]]
    printf 'PASS repair-plan-no-transfer\n'
  elif [[ $name == repair-failure ]]; then
    [[ $status == 1 ]] && [[ $(grep -c -- '--repair-venv --apply' "$dir/pct.log") == 1 ]]
    if grep -q 'rm -rf -- /run/ralf-bootstrap-install' "$dir/pct.log"; then return 1; fi
    printf 'PASS repair-failure-no-retry\n'
  else
    [[ $status == 0 ]] && grep -Fq 'Venv-Reparatur erfolgreich' <<<"$output"
    if grep -q '^push ' "$dir/pct.log"; then return 1; fi
    [[ $(grep -c -- '--repair-venv --apply' "$dir/pct.log") == 1 ]]
    [[ $(grep -c 'rm -rf -- /run/ralf-bootstrap-install' "$dir/pct.log") == 1 ]]
    printf 'PASS repair-apply-no-transfer\n'
  fi
}

run_normal_apply_rejects_moved() {
  local dir="$TEST_ROOT/normal-moved-reject" bin="$TEST_ROOT/normal-moved-reject/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  set +e
  output=$(TEST_REPAIR_STATE=1 PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'repair-venv' <<<"$output"
  if grep -q '^push ' "$dir/pct.log"; then return 1; fi
  printf 'PASS normal-apply-moved-rejection\n'
}

run_repair_validation_case() {
  local dir="$TEST_ROOT/repair-validation" bin="$TEST_ROOT/repair-validation/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  set +e
  output=$(TEST_REPAIR_VALIDATION_STATE=1 PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --plan --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == 0 ]] && grep -Fq 'recoverable_venv_repair_validation_failure' <<<"$output"
  if grep -q '^push ' "$dir/pct.log"; then return 1; fi
  [[ $(grep -c -- '--repair-venv --plan' "$dir/pct.log") == 1 ]]
  output=$(TEST_REPAIR_VALIDATION_STATE=1 PCT_LOG="$dir/pct-apply.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --apply --vmid 100 2>&1)
  grep -Fq 'Venv-Reparatur erfolgreich' <<<"$output"
  if grep -q '^push ' "$dir/pct-apply.log"; then return 1; fi
  [[ $(grep -c -- '--repair-venv --apply' "$dir/pct-apply.log") == 1 ]]
  printf 'PASS repair-validation-no-transfer\n'
}

run_normal_apply_rejects_validation() {
  local dir="$TEST_ROOT/normal-validation-reject" bin="$TEST_ROOT/normal-validation-reject/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  set +e
  output=$(TEST_REPAIR_VALIDATION_STATE=1 PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'recoverable_venv_repair_validation_failure' <<<"$output"
  if grep -q '^push ' "$dir/pct.log"; then return 1; fi
  printf 'PASS normal-apply-validation-rejection\n'
}

run_classifier_contract_case() {
  local name=$1 classify_output=$2 expected_fragment=$3
  local dir="$TEST_ROOT/$name" bin="$TEST_ROOT/$name/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  set +e
  output=$(TEST_REPAIR_VALIDATION_STATE=1 TEST_CLASSIFY_OUTPUT="$classify_output" \
    TEST_CLASSIFY_DIAGNOSTIC="failed_check=service_inactive_dead" \
    PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" \
    "$SCRIPT" --repair-venv --plan --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]]
  grep -Fq "$expected_fragment" <<<"$output"
  [[ $(grep -c -- '--classify --bundle' "$dir/pct.log") == 1 ]]
  if grep -q '^push ' "$dir/pct.log"; then return 1; fi
  printf 'PASS classifier-contract-%s\n' "$name"
}

run_partial_diagnostics_case() {
  local dir="$TEST_ROOT/classifier-partial" bin="$TEST_ROOT/classifier-partial/bin" output status
  mkdir -p "$bin"
  make_pct "$bin"
  set +e
  output=$(TEST_REPAIR_VALIDATION_STATE=1 TEST_CLASSIFY_OUTPUT=$'RALF_BOOTSTRAP_STATE_V1=partial\n' \
    TEST_CLASSIFY_DIAGNOSTIC=$'state=partial\nfailed_check=service_inactive_dead\nobserved_active_state=deactivating\nobserved_sub_state=stop-sigterm' \
    PCT_LOG="$dir/pct.log" PATH="$bin:/usr/bin:/bin" \
    "$SCRIPT" --repair-venv --plan --vmid 100 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]]
  grep -Fq 'failed_check=service_inactive_dead' <<<"$output"
  grep -Fq 'observed_active_state=deactivating' <<<"$output"
  grep -Fq 'benannten Prädikate' <<<"$output"
  printf 'PASS classifier-partial-diagnostics\n'
}

run_single_source_source_checks() {
  grep -Fq -- '--classify --bundle "$REMOTE_BUNDLE"' "$SCRIPT"
  if grep -Fq 'subprocess.run' "$SCRIPT" || grep -Fq 'service_state_is_inactive' "$SCRIPT"; then return 1; fi
  if grep -Fq 'import grp' "$SCRIPT" || grep -Fq 'import pwd' "$SCRIPT" || grep -Fq 'service_state_is_inactive' "$SCRIPT"; then return 1; fi
  printf 'PASS host-uses-guest-classifier-only\n'
}

run_unit_bundle_source_checks() {
  local unit="$PROJECT_ROOT/deploy/bootstrap-status/ralf-bootstrap.service"
  [[ $(grep -c -- '--no-control-socket' "$unit") == 1 ]]
  grep -Fxq 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK' "$unit"
  grep -Fq 'readonly UNIT_FILE="$PROJECT_ROOT/deploy/bootstrap-status/ralf-bootstrap.service"' "$SCRIPT"
  grep -Fq 'install -m 0640 "$UNIT_FILE" "$BUNDLE_DIR/ralf-bootstrap.service"' "$SCRIPT"
  printf 'PASS corrected-unit-enters-bundle\n'
}

run_case plan
run_case apply
run_case failure
run_resume_case resume-plan
run_resume_case resume-apply
run_resume_case resume-failure
run_normal_apply_rejects_resume
run_repair_case repair-plan
run_repair_case repair-apply
run_repair_case repair-failure
run_normal_apply_rejects_moved
run_repair_validation_case
run_normal_apply_rejects_validation
run_classifier_contract_case classifier-empty '' 'keine eindeutige RALF_BOOTSTRAP_STATE_V1-Zeile'
run_classifier_contract_case classifier-multiple $'RALF_BOOTSTRAP_STATE_V1=recoverable_venv_repair_validation_failure\nextra\n' 'mehrere oder zusätzliche stdout-Zeilen'
run_classifier_contract_case classifier-unknown $'RALF_BOOTSTRAP_STATE_V1=future_state\n' 'unbekannten Zustand'
run_classifier_contract_case classifier-noise $'Hinweis\nRALF_BOOTSTRAP_STATE_V1=recoverable_venv_repair_validation_failure\n' 'mehrere oder zusätzliche stdout-Zeilen'
run_partial_diagnostics_case
run_single_source_source_checks
run_unit_bundle_source_checks
