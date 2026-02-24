## Bootstrap Start Modes

### 1) Quick Start (unsafe)

```bash
curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh | bash
```

### 2) Danger Zone (recommended): pinned commit + SHA256 verify

```bash
set -euo pipefail
ORG="default82"; REPO="RALF"; COMMIT="<COMMIT_SHA_40>"; EXPECTED_SHA256="<START_SH_SHA256>"
URL="https://raw.githubusercontent.com/${ORG}/${REPO}/${COMMIT}/bootstrap/start.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$URL" -o "$tmp/start.sh"
echo "${EXPECTED_SHA256}  $tmp/start.sh" | sha256sum -c -
bash "$tmp/start.sh"
```

Maintainer hash generation:

```bash
sha256sum bootstrap/start.sh
git show <COMMIT_SHA>:bootstrap/start.sh | sha256sum
```

### 3) Production-ish (best): GitHub Release + minisign verify

Release assets:

- `start.sh`
- `start.sh.minisig`

User flow:

```bash
set -euo pipefail
ORG="default82"; REPO="RALF"; VERSION="<VERSION_TAG>"; PUBKEY="<MINISIGN_PUBLIC_KEY_STRING>"
BASE="https://github.com/${ORG}/${REPO}/releases/download/${VERSION}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE}/start.sh" -o "$tmp/start.sh"
curl -fsSL "${BASE}/start.sh.minisig" -o "$tmp/start.sh.minisig"
minisign -Vm "$tmp/start.sh" -P "$PUBKEY"
bash "$tmp/start.sh"
```

Maintainer setup (once):

```bash
minisign -G -p minisign.pub -s minisign.key
```

Per release:

```bash
minisign -S -s minisign.key -m bootstrap/start.sh -x start.sh.minisig
```

Publish only the minisign public key.

### GitHub Release Automation (CI)

The repo now includes:

- `.github/workflows/bootstrap-start-release.yml`
- `bootstrap/release/sign-start.sh`

Workflow behavior:

- Trigger on published GitHub releases (and `workflow_dispatch`)
- Build/sign release artifacts for `bootstrap/start.sh`
- Upload to the GitHub Release:
  - `start.sh`
  - `start.sh.minisig`
  - `start.sh.sha256`
  - `manifest.txt`

Required repository secret:

- `MINISIGN_SECRET_KEY_B64` : base64-encoded minisign secret key file contents

Recommended public key location in repo:

- `bootstrap/release/minisign.pub` (copy from `bootstrap/release/minisign.pub.example` and replace the placeholder)
- publish the same key in release notes/docs for out-of-band verification

Example secret creation:

```bash
base64 -w0 minisign.key
```

Local verification helper (optional):

```bash
bash bootstrap/release/verify-start.sh --version v1.0.0 --pubkey "<MINISIGN_PUBLIC_KEY_STRING>" --verify-only
```

## Bootstrap Engine Contract

`bootstrap/start.sh` is a thin launcher. It fetches the repo and delegates to:

```bash
./ralf bootstrap
```

The CLI always writes:

- `outputs/probe_report.json`
- `outputs/final_config.json`
- `outputs/checkpoints.json`
- `outputs/answers.yml`
- `outputs/plan_summary.md`
- `outputs/cli_status.json`

`cli_status.json` also includes:

- `adapter_report_file` (main adapter report path, if any)
- `adapter_report_exists` (`true|false`, useful for no-apply runs)
- `adapter_artifacts` (machine-readable artifact list with `exists=true|false`)

Example (`cli_status.json` excerpt):

```json
{
  "adapter_report_file": "/tmp/ralf-run/host_apply_report.json",
  "adapter_artifacts": [
    {
      "key": "host_runner_wrapper",
      "path": "/path/to/.ralf-host/bin/ralf-host-runner",
      "exists": true
    }
  ]
}
```

Optional:

- `OUTPUTS_DIR` / `--outputs-dir` to isolate outputs per run (useful for sequential comparisons)

Example:

```bash
OUTPUTS_DIR=/tmp/ralf-bootstrap-run1 ./ralf bootstrap --provisioner host --apply --yes
```

Exit codes:

- `0` ok
- `1` warn
- `2` blocker/error

Bootstrap phases:

1. Probe
2. Config merge (CLI > profile > defaults)
3. Policy / Gatekeeping
4. Provisioner
5. Artifact generation
6. Optional apply trigger (explicit only)

Provisioner adapter status:

- `proxmox_pct`: delegates to `bootstrap/legacy/start_proxmox_pct.sh`
- `host`: delegates to `bootstrap/legacy/start_host.sh` (minimal local apply: workspace prepare, no destructive changes, generates `ralf-host-runner`)
- `lxd`: delegates to `bootstrap/legacy/start_lxd.sh` (minimal apply: validates `lxc`/LXD, create-if-missing, stamps `user.ralf.*` metadata)
  - validates requested `LXD_PROFILE` before create/apply
  - writes LXD adapter artifacts under `OUTPUTS_DIR/lxd/` (`lxd-plan.md`, target/applied metadata JSON)

### Host Adapter Wrapper (`ralf-host-runner`)

The `host` adapter generates a helper wrapper at `.ralf-host/bin/ralf-host-runner`.

Current modes:

- `--check` : validate prerequisites and print derived paths
- `--dry-run` : print a preview of the future runner invocation
- `--status` : summarize generated host bootstrap artifacts/readiness
- `--artifacts` : list generated host bootstrap artifacts
- `--run` : guarded execution of `bootstrap/runner.sh` (requires `HOST_RUNNER_ENABLE_EXEC=1`; `AUTO_APPLY=1` also requires `HOST_RUNNER_ALLOW_APPLY=1`)
- `--json` : machine-readable output for `--status` / `--artifacts`
- `--quiet` : suppress contextual header lines (where applicable)

Examples:

```bash
.ralf-host/bin/ralf-host-runner --status
.ralf-host/bin/ralf-host-runner --status --json
.ralf-host/bin/ralf-host-runner --artifacts --json
HOST_RUNNER_ENABLE_EXEC=1 RUN_STACKS=0 .ralf-host/bin/ralf-host-runner --run
```

### LXD Adapter Artifacts

When `--provisioner lxd --apply` runs, the adapter writes:

- `lxd_apply_report.json` (main adapter report)
  - includes `profile_exists` and `metadata_diff`
- `lxd/lxd-plan.md` (conservative LXD action summary)
- `lxd/lxd-metadata-targets.json` (intended `user.ralf.*` values)
- `lxd/lxd-metadata-applied.json` (actual values after apply, if LXD apply succeeds)
