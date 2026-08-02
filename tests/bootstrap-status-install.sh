#!/usr/bin/env bash

# shellcheck disable=SC2016

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly SCRIPT="$PROJECT_ROOT/scripts/ralf-bootstrap-status-install.sh"
TEST_ROOT=$(mktemp -d)
trap 'find "$TEST_ROOT" -type f -delete; find "$TEST_ROOT" -depth -type d -empty -delete' EXIT

make_stub() {
  local dir=$1 name=$2 body=$3
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$body" >"$dir/$name"
  chmod +x "$dir/$name"
}

make_bundle() {
  local bundle=$1
  mkdir -p "$bundle"
  BUNDLE_PATH="$bundle" /usr/bin/python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile
import os
bundle = Path(os.environ["BUNDLE_PATH"])
wheel = bundle / "ralf_bootstrap-0.2.0-py3-none-any.whl"
with ZipFile(wheel, "w") as archive:
    archive.writestr("ralf_bootstrap-0.2.0.dist-info/METADATA", "Name: ralf-bootstrap\nVersion: 0.2.0\n")
    archive.writestr("ralf_bootstrap-0.2.0.dist-info/WHEEL", "Wheel-Version: 1.0\n")
PY
  printf '%s\n' '[storage]' 'database_path = "/var/lib/ralf/bootstrap/state.db"' >"$bundle/config.toml"
  printf '%s\n' 'Flask==3.1.3' 'Gunicorn==26.0.0' >"$bundle/runtime.lock"
  cp "$PROJECT_ROOT/deploy/bootstrap-status/ralf-bootstrap.service" "$bundle/ralf-bootstrap.service"
  cp "$SCRIPT" "$bundle/ralf-bootstrap-status-install.sh"
  (cd "$bundle" && sha256sum ralf_bootstrap-0.2.0-py3-none-any.whl runtime.lock config.toml ralf-bootstrap.service ralf-bootstrap-status-install.sh >SHA256SUMS)
}

make_stubs() {
  local bin=$1
  mkdir -p "$bin"
  make_stub "$bin" id 'if [[ ${TEST_NON_ROOT:-0} == 1 ]]; then printf "1000\n"; elif [[ ${1:-} == -Gn ]]; then printf "ralf-bootstrap\n"; else printf "0\n"; fi'
  make_stub "$bin" uname 'printf "x86_64\n"'
  make_stub "$bin" systemctl 'case "$1" in is-system-running) printf "running\n";; is-enabled) [[ -f "$TEST_STATE/service-enabled" || -f "$TEST_STATE/service" ]] && printf "enabled\n" || exit 1;; is-active) [[ -f "$TEST_STATE/service" ]] && printf "active\n" || exit 1;; enable) touch "$TEST_STATE/service-enabled";; start) touch "$TEST_STATE/service";; stop) rm -f "$TEST_STATE/service";; reset-failed) touch "$TEST_STATE/reset-failed";; daemon-reload|status) :;; show) active=${TEST_SYSTEMD_ACTIVE:-inactive}; sub=${TEST_SYSTEMD_SUB:-dead}; if [[ ${TEST_SYSTEMD_SEQUENCE:-} == transient-then-stable ]]; then count=$(cat "$TEST_STATE/show-count" 2>/dev/null || printf 0); count=$((count + 1)); printf "%s\n" "$count" >"$TEST_STATE/show-count"; if ((count < 3)); then active=deactivating; sub=stop-sigterm; fi; fi; printf "%s\n" "LoadState=loaded" "UnitFileState=$([[ -f "$TEST_STATE/service-enabled" || -f "$TEST_STATE/service" ]] && printf enabled || printf disabled)" "ActiveState=$active" "SubState=$sub" "Result=exit-code" "ExecMainCode=1" "ExecMainStatus=203";; *) exit 0;; esac'
  make_stub "$bin" ip 'printf "default via 192.0.2.1 dev eth0\n"'
  make_stub "$bin" getent 'case "$1" in ahostsv4) printf "192.0.2.1 STREAM archive.ubuntu.com\n";; passwd) [[ -f "$TEST_STATE/user" ]] && printf "ralf-bootstrap:x:997:997::/nonexistent:/usr/sbin/nologin\n" || exit 2;; group) [[ -f "$TEST_STATE/group" ]] && printf "ralf-bootstrap:x:997:\n" || exit 2;; esac'
  make_stub "$bin" dpkg 'exit 0'
  make_stub "$bin" pgrep 'exit 1'
  make_stub "$bin" fuser 'exit 1'
  make_stub "$bin" wget 'exit 0'
  make_stub "$bin" groupadd 'touch "$TEST_STATE/group"; printf "groupadd\n" >>"$TEST_LOG"'
  make_stub "$bin" useradd 'touch "$TEST_STATE/user"; printf "useradd\n" >>"$TEST_LOG"'
  make_stub "$bin" apt-cache 'if [[ ${TEST_NO_CANDIDATE:-0} == 1 ]]; then printf "%s\n" "Installed: (none)" "Candidate: (none)"; else printf "%s\n" "Installed: (none)" "Candidate: 3.14.4-1" " 500 http://archive.ubuntu.com/ubuntu resolute-updates/main amd64 Packages"; fi'
  make_stub "$bin" apt-get 'printf "apt-get %s\n" "$*" >>"$TEST_LOG"; [[ ${TEST_APT_FAIL:-0} == 1 ]] && exit 23; touch "$TEST_STATE/apt-installed"'
  make_stub "$bin" chown '[[ ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 ]] && touch "$TEST_STATE/venv-chowned"; exit 0'
  make_stub "$bin" chmod '[[ ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 && "$*" == *"0750"* ]] && touch "$TEST_STATE/venv-mode-final"; exec /usr/bin/chmod "$@"'
  make_stub "$bin" systemd-analyze 'exit 0'
  make_stub "$bin" stat 'case "$*" in *"VERSION"*) printf "root:ralf-bootstrap|640\n";; *"config.toml"*) printf "root:ralf-bootstrap|640\n";; *"runtime.lock"*|*".whl"*) printf "root:ralf-bootstrap|640\n";; *"ralf-bootstrap.service"*) printf "root:root|644\n";; *".venv-repair-in-progress"*) printf "root:ralf-bootstrap|640\n";; *"/var/lib/ralf/bootstrap"*) printf "ralf-bootstrap:ralf-bootstrap|750\n";; *"/venv"*) if [[ ${TEST_REPAIR_VALIDATION_STATE:-0} == 1 && ! -f "$TEST_STATE/venv-mode-final" ]]; then printf "root:root|755\n"; else printf "root:ralf-bootstrap|750\n"; fi;; *) printf "root:ralf-bootstrap|750\n";; esac'
  make_stub "$bin" install 'args=(); while (($#)); do case $1 in -o|-g) shift;; *) args+=("$1");; esac; shift; done; exec /usr/bin/install "${args[@]}"'
  make_stub "$bin" python3 'if [[ ${1:-} == --version ]]; then printf "Python %s\n" "${TEST_PY_VERSION:-3.14.4}"; elif [[ ${1:-} == -c && ${2:-} == *ensurepip* ]]; then if [[ ${TEST_ENSUREPIP:-1} == 1 || -f "$TEST_STATE/apt-installed" ]]; then printf "25.0.1\n"; else exit 1; fi; elif [[ ${1:-} == -c && ${2:-} == *sys.version_info* ]]; then printf "%s\n" "${TEST_PY_VERSION:-3.14.4}"; elif [[ ${1:-} == -c && ${2:-} == *socket* && ${TEST_PORT_BUSY:-0} == 1 ]]; then exit 1; elif [[ ${1:-} == -m && ${2:-} == venv && ${3:-} == --help ]]; then printf "usage: venv\n"; elif [[ ${1:-} == -m && ${2:-} == venv && ${3:-} != --help ]]; then [[ ${TEST_VENV_FAIL:-0} == 1 ]] && exit 23; dir=$3; mkdir -p "$dir/bin"; printf "venv-created\n" >>"$TEST_LOG"; printf "home = /usr/bin\n" >"$dir/pyvenv.cfg"; printf "%s\n" "#!/usr/bin/env bash" "if [[ \${1:-} == -m && \${2:-} == pip ]]; then printf \"pip from $dir\\n\"; else exit 0; fi" >"$dir/bin/python"; printf "%s\n" "#!$dir/bin/python" "exit 0" >"$dir/bin/gunicorn"; chmod +x "$dir/bin/python" "$dir/bin/gunicorn"; elif [[ ${1:-} == - && ${TEST_PORT_BUSY:-0} == 1 ]]; then exit 1; elif [[ ${1:-} == - ]]; then exit 0; elif [[ ${1:-} == -c ]]; then exit 0; else exec /usr/bin/python3 "$@"; fi'
}

run_case() {
  local mode=$1 name=$2
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"
  make_stubs "$bin"
  local output status
  set +e
  output=$(TEST_NON_ROOT="$([[ $name == non-root ]] && printf 1 || printf 0)" TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" "--$mode" --bundle "$bundle" 2>&1)
  status=$?
  set -e
  if [[ $name == non-root ]]; then
    [[ $status == 1 ]] && grep -Fq 'root ausgeführt' <<<"$output"
    printf 'PASS non-root\n'
  elif [[ $mode == plan ]]; then
    [[ $status == 0 ]] && grep -Fq 'es wurden noch keine Installationsmutationen ausgeführt' <<<"$output"
    [[ ! -e "$root/opt" ]]
    printf 'PASS plan-no-mutation\n'
  else
    [[ $status == 0 ]] && grep -Fq 'Installation erfolgreich' <<<"$output"
    [[ -d "$root/opt/ralf/bootstrap/app" && -d "$root/opt/ralf/bootstrap/venv" ]]
    [[ -f "$root/etc/ralf/bootstrap/config.toml" && ! -e "$root/var/lib/ralf/bootstrap/state.db" ]]
    printf 'PASS apply-installation\n'
    output=$(TEST_STATE="$state" RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --bundle "$bundle" 2>&1)
    grep -Fq 'Bereits vollständige Installation erkannt' <<<"$output"
    printf 'PASS apply-idempotent\n'
  fi
}

run_bundle_failure() {
  local name=$1
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"
  make_stubs "$bin"
  if [[ $name == bad-checksum ]]; then printf '%s\n' 'broken' >"$bundle/SHA256SUMS"; fi
  if [[ $name == partial ]]; then mkdir -p "$root/opt/ralf/bootstrap"; fi
  local output status
  set +e
  output=$(TEST_PORT_BUSY="$([[ $name == busy-port ]] && printf 1 || printf 0)" TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --plan --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]]
  [[ $name != busy-port || -z $output ]]
  if [[ $name != busy-port ]]; then grep -Fq 'Fehler:' <<<"$output"; fi
  printf 'PASS %s\n' "$name"
}

run_missing_ensurepip_plan() {
  local name=missing-ensurepip output
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"; make_stubs "$bin"
  TEST_STATE="$state" TEST_ENSUREPIP=0 PATH="$bin:/usr/bin:/bin" "$bin/python3" -m venv --help >/dev/null
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=0 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --plan --bundle "$bundle" 2>&1)
  grep -Fq 'python3.14-venv' <<<"$output"
  [[ ! -e "$state/apt-installed" && ! -e "$root/opt" ]]
  printf 'PASS ensurepip-missing-plan\n'
}

run_failure_case() {
  local name=$1 output status
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"; make_stubs "$bin"
  set +e
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=0 TEST_APT_FAIL=1 TEST_NO_CANDIDATE="$([[ $name == no-candidate ]] && printf 1 || printf 0)" TEST_PY_VERSION="$([[ $name == bad-python ]] && printf invalid || printf 3.14.4)" RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'Fehler:' <<<"$output"
  if [[ $name == apt-failure ]]; then
    [[ ! -e "$state/apt-installed" ]] && ! grep -q venv-created "$state/commands.log" 2>/dev/null
  fi
  printf 'PASS %s\n' "$name"
}

run_resume_case() {
  local name=$1 output status
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$root/opt/ralf/bootstrap/.venv-build.failed" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  touch "$state/user" "$state/group"
  make_bundle "$bundle"; make_stubs "$bin"
  set +e
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=0 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --resume --plan --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 0 ]] && grep -Fq 'recoverable_venv_failure' <<<"$output"
  [[ -d "$root/opt/ralf/bootstrap/.venv-build.failed" && ! -e "$state/apt-installed" ]]
  printf 'PASS resume-plan\n'
  set +e
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=0 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'verwende ausdrücklich --resume --apply' <<<"$output"
  printf 'PASS normal-apply-rejects-resume-state\n'
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=0 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --resume --apply --bundle "$bundle" 2>&1)
  grep -Fq 'Installation erfolgreich' <<<"$output"
  [[ ! -e "$root/opt/ralf/bootstrap/.venv-build.failed" && -d "$root/opt/ralf/bootstrap/venv" ]]
  grep -Fq 'apt-get install' "$state/commands.log"
  [[ $(grep -n 'apt-get install' "$state/commands.log" | cut -d: -f1) -lt $(grep -n '^venv-created$' "$state/commands.log" | cut -d: -f1) ]]
  [[ $(grep -Ec '^(groupadd|useradd)$' "$state/commands.log" || true) == 0 ]]
  [[ ! -e "$root/var/lib/ralf/bootstrap/state.db" ]]
  printf 'PASS resume-apply\n'
}

run_resume_rejection() {
  local name=$1
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state" output status
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$root/opt/ralf/bootstrap/.venv-build.one" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  touch "$state/user" "$state/group"
  case $name in
    two-venvs) mkdir "$root/opt/ralf/bootstrap/.venv-build.two" ;;
    app-temp) mkdir "$root/opt/ralf/bootstrap/.app-build.one" ;;
    state-db) mkdir -p "$root/var/lib/ralf/bootstrap"; touch "$root/var/lib/ralf/bootstrap/state.db" ;;
    unit) mkdir -p "$root/etc/systemd/system"; touch "$root/etc/systemd/system/ralf-bootstrap.service" ;;
    invalid-bundle) ;;
  esac
  make_bundle "$bundle"; make_stubs "$bin"
  [[ $name != invalid-bundle ]] || printf 'broken\n' >"$bundle/SHA256SUMS"
  set +e
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=0 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --resume --plan --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'Fehler:' <<<"$output"
  [[ -d "$root/opt/ralf/bootstrap/.venv-build.one" && ! -e "$state/apt-installed" ]]
  printf 'PASS resume-rejects-%s\n' "$name"
}

make_moved_install() {
  local root=$1 bundle=$2
  mkdir -p "$root/opt/ralf/bootstrap/app" "$root/opt/ralf/bootstrap/venv/bin" \
    "$root/etc/ralf/bootstrap" "$root/etc/systemd/system" "$root/var/lib/ralf/bootstrap"
  cp "$bundle/"* "$root/opt/ralf/bootstrap/app/" 2>/dev/null || true
  rm -f "$root/opt/ralf/bootstrap/app/SHA256SUMS" "$root/opt/ralf/bootstrap/app/config.toml" "$root/opt/ralf/bootstrap/app/ralf-bootstrap.service" "$root/opt/ralf/bootstrap/app/ralf-bootstrap-status-install.sh"
  cp "$bundle/$WHEEL_NAME" "$root/opt/ralf/bootstrap/app/$WHEEL_NAME"
  cp "$bundle/runtime.lock" "$root/opt/ralf/bootstrap/app/runtime.lock"
  cp "$bundle/config.toml" "$root/etc/ralf/bootstrap/config.toml"
  cp "$bundle/ralf-bootstrap.service" "$root/etc/systemd/system/ralf-bootstrap.service"
  printf '%s\n' '0.2.0' >"$root/opt/ralf/bootstrap/VERSION"
  printf 'home = /usr/bin\n' >"$root/opt/ralf/bootstrap/venv/pyvenv.cfg"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$root/opt/ralf/bootstrap/venv/bin/python"
  printf '%s\n' '#!/opt/ralf/bootstrap/.venv-build.WydEtv/bin/python' 'exit 0' >"$root/opt/ralf/bootstrap/venv/bin/gunicorn"
  chmod +x "$root/opt/ralf/bootstrap/venv/bin/python" "$root/opt/ralf/bootstrap/venv/bin/gunicorn"
  touch "$root/opt/ralf/bootstrap/.keep"
  rm -f "$root/opt/ralf/bootstrap/.keep"
}

run_repair_venv_case() {
  local name=$1
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state" output status
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"
  WHEEL_NAME=ralf_bootstrap-0.2.0-py3-none-any.whl
  make_moved_install "$root" "$bundle"
  make_stubs "$bin"
  touch "$state/user" "$state/group" "$state/service-enabled"
  set +e
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --plan --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 0 ]] && grep -Fq 'recoverable_moved_venv_exec_failure' <<<"$output"
  [[ -f "$root/opt/ralf/bootstrap/venv/bin/gunicorn" && ! -e "$state/apt-installed" ]]
  printf 'PASS repair-venv-plan\n'
  if [[ $name == repair-failure ]]; then
    set +e
    output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 TEST_VENV_FAIL=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --apply --bundle "$bundle" 2>&1)
    status=$?
    set -e
    [[ $status == 1 && -f "$root/opt/ralf/bootstrap/.venv-repair-in-progress" ]]
    [[ ! -e "$state/service" ]]
    printf 'PASS repair-venv-failure-marker\n'
    return
  fi
  set +e
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'repair-venv' <<<"$output"
  [[ ! -e "$state/service" ]]
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --apply --bundle "$bundle" 2>&1)
  grep -Fq 'Venv-Reparatur erfolgreich' <<<"$output"
  [[ -d "$root/opt/ralf/bootstrap/venv" && ! -e "$root/opt/ralf/bootstrap/.venv-repair-in-progress" ]]
  [[ $(grep -c '^venv-created$' "$state/commands.log") == 1 ]]
  [[ $(grep -Ec '^(groupadd|useradd)$' "$state/commands.log" || true) == 0 ]]
  [[ $(grep -c '^apt-get' "$state/commands.log" || true) == 0 ]]
  printf 'PASS repair-venv-apply\n'
}

make_repair_validation_install() {
  local root=$1 bundle=$2
  mkdir -p "$root/opt/ralf/bootstrap/app" "$root/opt/ralf/bootstrap/venv/bin" \
    "$root/etc/ralf/bootstrap" "$root/etc/systemd/system" "$root/var/lib/ralf/bootstrap"
  cp "$bundle/$WHEEL_NAME" "$root/opt/ralf/bootstrap/app/$WHEEL_NAME"
  cp "$bundle/runtime.lock" "$root/opt/ralf/bootstrap/app/runtime.lock"
  cp "$bundle/config.toml" "$root/etc/ralf/bootstrap/config.toml"
  cp "$bundle/ralf-bootstrap.service" "$root/etc/systemd/system/ralf-bootstrap.service"
  printf '%s\n' '0.2.0' >"$root/opt/ralf/bootstrap/VERSION"
  printf 'home = /usr/bin\n' >"$root/opt/ralf/bootstrap/venv/pyvenv.cfg"
  cat >"$root/opt/ralf/bootstrap/venv/bin/python" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == -m && ${2:-} == pip ]]; then
  printf 'pip 25.1.1 from %s/lib/python3.14/site-packages/pip (python 3.14)\n' "${TEST_VENV_DIR:-/opt/ralf/bootstrap/venv}"
fi
exit 0
EOF
  printf '%s\n' "#!$root/opt/ralf/bootstrap/venv/bin/python" 'exit 0' >"$root/opt/ralf/bootstrap/venv/bin/gunicorn"
  chmod +x "$root/opt/ralf/bootstrap/venv/bin/python" "$root/opt/ralf/bootstrap/venv/bin/gunicorn"
  printf 'bootstrap_version=0.2.0\noperation=repair-venv\n' >"$root/opt/ralf/bootstrap/.venv-repair-in-progress"
}

run_repair_validation_case() {
  local root="$TEST_ROOT/repair-validation/root" bundle="$TEST_ROOT/repair-validation/bundle" bin="$TEST_ROOT/repair-validation/bin" state="$TEST_ROOT/repair-validation/state" output status
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"
  WHEEL_NAME=ralf_bootstrap-0.2.0-py3-none-any.whl
  make_repair_validation_install "$root" "$bundle"
  make_stubs "$bin"
  touch "$state/user" "$state/group" "$state/service-enabled"
  set +e
  output=$(TEST_REPAIR_VALIDATION_STATE=1 TEST_VENV_DIR="$root/opt/ralf/bootstrap/venv" TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --plan --bundle "$bundle" 2>&1)
  status=$?
  set -e
  if [[ $status != 0 ]]; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  grep -Fq 'recoverable_venv_repair_validation_failure' <<<"$output"
  [[ -f "$root/opt/ralf/bootstrap/.venv-repair-in-progress" && ! -e "$state/venv-mode-final" ]]
  set +e
  output=$(TEST_REPAIR_VALIDATION_STATE=1 TEST_VENV_DIR="$root/opt/ralf/bootstrap/venv" TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]] && grep -Fq 'recoverable_venv_repair_validation_failure' <<<"$output"
  [[ ! -e "$state/venv-mode-final" && ! -e "$state/reset-failed" && ! -e "$state/service" ]]
  output=$(TEST_REPAIR_VALIDATION_STATE=1 TEST_VENV_DIR="$root/opt/ralf/bootstrap/venv" TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --repair-venv --apply --bundle "$bundle" 2>&1)
  grep -Fq 'Venv-Reparaturfortsetzung erfolgreich' <<<"$output"
  [[ -f "$state/reset-failed" && -f "$state/service" ]]
  [[ ! -e "$root/opt/ralf/bootstrap/.venv-repair-in-progress" ]]
  [[ ! -e "$state/apt-installed" && ! -e "$state/venv-created" ]]
  printf 'PASS repair-validation-resume\n'
}

run_classification_case() {
  local name=$1 expected=$2
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  local stdout_file="$TEST_ROOT/$name/stdout" stderr_file="$TEST_ROOT/$name/stderr"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  make_bundle "$bundle"
  WHEEL_NAME=ralf_bootstrap-0.2.0-py3-none-any.whl
  make_repair_validation_install "$root" "$bundle"
  make_stubs "$bin"
  touch "$state/user" "$state/group" "$state/service-enabled"
  TEST_REPAIR_VALIDATION_STATE=1 \
    TEST_SYSTEMD_ACTIVE="${TEST_CLASSIFY_ACTIVE:-inactive}" \
    TEST_SYSTEMD_SUB="${TEST_CLASSIFY_SUB:-dead}" \
    TEST_SYSTEMD_SEQUENCE="${TEST_CLASSIFY_SEQUENCE:-}" \
    TEST_VENV_DIR="$root/opt/ralf/bootstrap/venv" TEST_STATE="$state" TEST_LOG="$state/commands.log" \
    RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" \
    "$SCRIPT" --classify --bundle "$bundle" >"$stdout_file" 2>"$stderr_file"
  [[ $(wc -l <"$stdout_file") == 1 ]]
  [[ $(cat "$stdout_file") == "RALF_BOOTSTRAP_STATE_V1=$expected" ]]
  [[ ! -e "$state/reset-failed" && ! -e "$state/service" && ! -e "$state/venv-chowned" && ! -e "$state/venv-mode-final" ]]
  [[ -f "$root/opt/ralf/bootstrap/.venv-repair-in-progress" ]]
  if [[ $expected == partial ]]; then
    grep -Fxq 'state=partial' "$stderr_file"
    grep -Fxq 'failed_check=service_inactive_dead' "$stderr_file"
    grep -Fxq "observed_active_state=${TEST_CLASSIFY_ACTIVE}" "$stderr_file"
    grep -Fxq "observed_sub_state=${TEST_CLASSIFY_SUB}" "$stderr_file"
  else
    [[ ! -s $stderr_file ]]
  fi
  printf 'PASS classify-%s\n' "$name"
}

run_classification_bundle_failure() {
  local name=classify-invalid-bundle root="$TEST_ROOT/classify-invalid-bundle/root" bundle="$TEST_ROOT/classify-invalid-bundle/bundle"
  local bin="$TEST_ROOT/classify-invalid-bundle/bin" state="$TEST_ROOT/classify-invalid-bundle/state"
  mkdir -p "$root/etc" "$state"
  make_bundle "$bundle"; make_stubs "$bin"
  printf 'broken\n' >"$bundle/SHA256SUMS"
  TEST_STATE="$state" RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" \
    "$SCRIPT" --classify --bundle "$bundle" >"$TEST_ROOT/$name/stdout" 2>"$TEST_ROOT/$name/stderr"
  [[ $(cat "$TEST_ROOT/$name/stdout") == 'RALF_BOOTSTRAP_STATE_V1=partial' ]]
  grep -Fxq 'failed_check=bundle_valid' "$TEST_ROOT/$name/stderr"
  printf 'PASS classify-invalid-bundle\n'
}

run_direct_venv_source_checks() {
  if grep -Fq 'mv "$temp_venv" "$venv_dir"' "$SCRIPT"; then return 1; fi
  if grep -Fq 'sed' "$SCRIPT"; then return 1; fi
  if grep -Eq '(^|[[:space:]])(cp|rsync)[[:space:]].*venv' "$SCRIPT"; then return 1; fi
  grep -Fq 'python3 -m venv "$venv_dir"' "$SCRIPT"
  printf 'PASS direct-venv-source-checks\n'
}

run_real_venv_semantics() {
  local root="$TEST_ROOT/real-venv" symlink_venv="$TEST_ROOT/real-venv/symlink" copies_venv="$TEST_ROOT/real-venv/copies"
  mkdir -p "$root"
  python3 -m venv "$symlink_venv"
  python3 -m venv --copies "$copies_venv"
  if [[ ! -L "$symlink_venv/bin/python" ]]; then
    ln -sf "$(readlink -f "$(command -v python3)")" "$symlink_venv/bin/python"
  fi
  [[ -L "$symlink_venv/bin/python" && ! -L "$copies_venv/bin/python" ]]
  for venv_path in "$symlink_venv" "$copies_venv"; do
    "$venv_path/bin/python" - "$venv_path" <<'PY'
import os
import pathlib
import sys
import sysconfig

expected = pathlib.Path(sys.argv[1]).resolve()
assert pathlib.Path(sys.prefix).resolve() == expected
assert pathlib.Path(sys.exec_prefix).resolve() == expected
assert sys.prefix != sys.base_prefix
assert sys.exec_prefix != sys.base_exec_prefix
assert sys.executable
assert os.path.samefile(sys.executable, expected / 'bin/python')
assert pathlib.Path(sysconfig.get_paths()['purelib']).resolve().is_relative_to(expected)
PY
  done
  printf 'PASS real-venv-symlink-and-copies\n'
}

run_direct_resume_case() {
  local name=direct-resume output
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$root/opt/ralf/bootstrap/venv" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' 'VERSION_CODENAME=resolute' >"$root/etc/os-release"
  printf 'bootstrap_version=0.2.0\noperation=install-venv\n' >"$root/opt/ralf/bootstrap/.venv-install-in-progress"
  printf 'home = /usr/bin\n' >"$root/opt/ralf/bootstrap/venv/pyvenv.cfg"
  touch "$state/user" "$state/group"
  make_bundle "$bundle"; make_stubs "$bin"
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --resume --plan --bundle "$bundle" 2>&1)
  grep -Fq 'recoverable_direct_venv_failure' <<<"$output"
  output=$(TEST_STATE="$state" TEST_LOG="$state/commands.log" TEST_ENSUREPIP=1 RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --resume --apply --bundle "$bundle" 2>&1)
  grep -Fq 'Installation erfolgreich' <<<"$output"
  [[ -d "$root/opt/ralf/bootstrap/venv" && ! -e "$root/opt/ralf/bootstrap/.venv-install-in-progress" ]]
  printf 'PASS direct-venv-resume\n'
}

run_case plan plan
run_case apply apply
run_case apply non-root
run_bundle_failure bad-checksum
run_bundle_failure busy-port
run_bundle_failure partial
run_missing_ensurepip_plan
run_failure_case no-candidate
run_failure_case bad-python
run_failure_case apt-failure
run_resume_case recoverable
run_resume_rejection two-venvs
run_resume_rejection app-temp
run_resume_rejection state-db
run_resume_rejection unit
run_resume_rejection invalid-bundle
run_direct_venv_source_checks
run_real_venv_semantics
run_direct_resume_case
run_repair_venv_case moved
run_repair_venv_case repair-failure
run_repair_validation_case
run_classification_case classify-current recoverable_venv_repair_validation_failure
TEST_CLASSIFY_ACTIVE=activating TEST_CLASSIFY_SUB=auto-restart run_classification_case classify-transient partial
TEST_CLASSIFY_SEQUENCE=transient-then-stable run_classification_case classify-stabilizes recoverable_venv_repair_validation_failure
run_classification_bundle_failure
