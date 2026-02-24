#!/usr/bin/env bash
set -euo pipefail

# Local bootstrap selfcheck mirroring the CI workflow as closely as practical.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="full"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick) mode="quick"; shift ;;
    -h|--help)
      cat <<'EOF'
Usage: bootstrap/selfcheck.sh [--quick]

Runs local bootstrap selfchecks (syntax, CLI, launcher, helpers).
EOF
      exit 0
      ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

cd "$repo_root"

echo "[selfcheck] syntax"
bash -n bootstrap/start.sh
bash -n bin/ralf
bash -n ralf
bash -n bootstrap/legacy/start_host.sh
bash -n bootstrap/legacy/start_lxd.sh
bash -n bootstrap/release/sign-start.sh
bash -n bootstrap/release/verify-start.sh
bash -n bootstrap/release/print-start-integrity.sh

echo "[selfcheck] cli paths"
./ralf bootstrap --provisioner host --outputs-dir /tmp/ralf-host-noapply >/dev/null || test $? -eq 1
./ralf bootstrap --provisioner host --apply --yes --outputs-dir /tmp/ralf-host-apply >/dev/null
TUI=1 NON_INTERACTIVE=1 ./ralf bootstrap --provisioner host --outputs-dir /tmp/ralf-host-tui-ni >/dev/null || test $? -eq 1
./ralf bootstrap --provisioner host --answers-file bootstrap/examples/answers.generic_home.yml --outputs-dir /tmp/ralf-host-answers >/dev/null || test $? -eq 1
./ralf bootstrap --provisioner lxd --outputs-dir /tmp/ralf-lxd-noapply >/dev/null || test $? -eq 1
./ralf bootstrap --provisioner lxd --apply --outputs-dir /tmp/ralf-lxd-apply >/dev/null || test $? -eq 2

python3 - <<'PY'
import json
checks = {
    "host_noapply": ("/tmp/ralf-host-noapply/cli_status.json", "warn", False),
    "host_apply": ("/tmp/ralf-host-apply/cli_status.json", "ok", True),
    "lxd_noapply": ("/tmp/ralf-lxd-noapply/cli_status.json", "warn", False),
    "lxd_apply": ("/tmp/ralf-lxd-apply/cli_status.json", "blocker", True),
}
for name, (path, expected_status, expected_report_exists) in checks.items():
    d = json.load(open(path))
    assert d["status"] == expected_status, (name, d["status"], expected_status)
    assert d["adapter_report_exists"] == expected_report_exists, (name, d["adapter_report_exists"], expected_report_exists)

tui_cfg = json.load(open("/tmp/ralf-host-tui-ni/final_config.json"))
tui_status = json.load(open("/tmp/ralf-host-tui-ni/cli_status.json"))
assert tui_cfg["tui_requested"] == 1 and tui_cfg["tui"] == 0 and tui_cfg["non_interactive"] == 1
assert tui_status["tui_requested"] == 1 and tui_status["tui_effective"] == 0
assert any("disables TUI" in w for w in tui_status["warnings"])

answers_cfg = json.load(open("/tmp/ralf-host-answers/final_config.json"))
assert answers_cfg["network_cidr"] == "192.168.178.0/24"
assert answers_cfg["base_domain"] == "home.lan"
assert answers_cfg["ct_hostname"] == "ralf-bootstrap"
print("[selfcheck] cli json assertions ok")
PY

echo "[selfcheck] launcher tui/non-interactive hint"
ref_now="$(git rev-parse --short HEAD)"
hint_out=/tmp/ralf-launch-tui-ni-hint
rm -rf "$hint_out"
TUI=1 NON_INTERACTIVE=1 PROVISIONER=host OUTPUTS_DIR="$hint_out" \
  RALF_REPO_URL="file://${repo_root}" RALF_REF="$ref_now" \
  bash bootstrap/start.sh >/tmp/ralf-launch-tui-ni-hint.log 2>&1 || true
grep -q 'TUI requested with NON_INTERACTIVE=1; CLI policy will disable TUI' /tmp/ralf-launch-tui-ni-hint.log
echo "[selfcheck] launcher tui/non-interactive hint ok"

echo "[selfcheck] integrity helper"
bash bootstrap/release/print-start-integrity.sh --commit HEAD > /tmp/ralf-start-integrity.txt
bash bootstrap/release/print-start-integrity.sh --json > /tmp/ralf-start-integrity.json
grep -q '^COMMIT=' /tmp/ralf-start-integrity.txt
grep -q '^SHA256=' /tmp/ralf-start-integrity.txt
python3 - <<'PY'
import json
d = json.load(open("/tmp/ralf-start-integrity.json"))
assert len(d["commit"]) == 40
assert d["file"] == "bootstrap/start.sh"
assert len(d["sha256"]) == 64
print("[selfcheck] integrity helper ok")
PY

echo "[selfcheck] verify helper (mocked minisign/curl)"
mockdir=/tmp/ralf-verify-helper-mock
rm -rf "$mockdir"
mkdir -p "$mockdir/bin"
cat > "$mockdir/bin/minisign" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$mockdir/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" ]] || exit 2
printf 'dummy' > "$out"
EOF
chmod +x "$mockdir/bin/minisign" "$mockdir/bin/curl"
cat > /tmp/ralf-minisign.pub <<'EOF'
untrusted comment: test
RWQTESTKEYSTRING
EOF
PATH="$mockdir/bin:$PATH" bash bootstrap/release/verify-start.sh \
  --version v0 --pubkey-file /tmp/ralf-minisign.pub --verify-only \
  >/tmp/ralf-verify-helper.out 2>/tmp/ralf-verify-helper.err
grep -q '\[verify-start\] verified:' /tmp/ralf-verify-helper.out
echo "[selfcheck] verify helper ok"

if [[ "$mode" != "quick" ]]; then
  echo "[selfcheck] launcher paths"
  ref="$(git rev-parse --short HEAD)"
  out=/tmp/ralf-launch-selfcheck
  rm -rf "$out"
  logf=/tmp/ralf-launch-selfcheck.log
  OUTPUTS_DIR="$out" PROVISIONER=host YES=1 APPLY=1 \
    RALF_REPO_URL="file://${repo_root}" RALF_REF="$ref" \
    bash bootstrap/start.sh >"$logf" 2>&1

  python3 - <<'PY'
import json
d = json.load(open("/tmp/ralf-launch-selfcheck/cli_status.json"))
assert d["status"] == "ok", d
assert d["adapter_report_exists"] is True, d
assert len(d.get("adapter_artifacts", [])) >= 1, d
print("[selfcheck] launcher host path ok")
PY
  grep -q 'Resolved git checkout to commit ' "$logf"
  echo "[selfcheck] launcher resolved commit log ok"

  tag="local-bootstrap-selfcheck-tag"
  git tag -f "$tag" >/dev/null
  trap 'git tag -d "$tag" >/dev/null 2>&1 || true' EXIT
  out=/tmp/ralf-launch-selfcheck-tag
  rm -rf "$out"
  OUTPUTS_DIR="$out" PROVISIONER=host YES=1 APPLY=1 \
    RALF_REPO_URL="file://${repo_root}" RALF_REF="$tag" \
    bash bootstrap/start.sh >/dev/null
  python3 - <<'PY'
import json
d = json.load(open("/tmp/ralf-launch-selfcheck-tag/cli_status.json"))
assert d["status"] == "ok", d
print("[selfcheck] launcher tag path ok")
PY

  work=/tmp/ralf-launch-relative-args-local-selfcheck
  rm -rf "$work"
  mkdir -p "$work"
  cp bootstrap/examples/answers.generic_home.yml "$work/answers.yml"
  (
    cd "$work"
    PROVISIONER=host YES=1 APPLY=1 \
      ANSWERS_FILE=answers.yml \
      EXPORT_ANSWERS=exported/answers.out.yml \
      OUTPUTS_DIR=outs \
      RALF_REPO_URL="file://${repo_root}" RALF_REF="$ref" \
      bash "${repo_root}/bootstrap/start.sh" >/dev/null
  )
  python3 - <<'PY'
import json, os
base = "/tmp/ralf-launch-relative-args-local-selfcheck"
d = json.load(open(base + "/outs/cli_status.json"))
assert d["status"] == "ok", d
assert d["outputs_dir"] == base + "/outs", d
assert os.path.exists(base + "/exported/answers.out.yml")
print("[selfcheck] launcher relative path args ok")
PY
fi

echo "[selfcheck] PASS (${mode})"
