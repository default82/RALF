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
