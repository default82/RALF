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
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' 'printf "%s\n" "$*" >>"$PCT_LOG"' 'if [[ $1 == status ]]; then printf "status: running\n"; elif [[ $1 == config ]]; then printf "hostname: ralf-standalone\n"; elif [[ $1 == pending ]]; then printf "cur hostname: ralf-standalone\n"; elif [[ $1 == exec ]]; then shift 3; if [[ ${1:-} == python3 && ${2:-} == --version ]]; then printf "Python 3.14.4\n"; elif [[ ${1:-} == python3 && ${2:-} == -m ]]; then printf "usage: venv\n"; elif [[ ${1:-} == python3 && ${2:-} == -c ]]; then printf "absent\n"; elif [[ ${1:-} == getent ]]; then exit 2; elif [[ ${1:-} == bash && ${TEST_GUEST_FAILURE:-0} == 1 ]]; then exit 17; fi; elif [[ $1 == push ]]; then :; else exit 2; fi' >"$dir/pct"
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

run_case plan
run_case apply
run_case failure
