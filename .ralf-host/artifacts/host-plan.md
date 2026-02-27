# Host Bootstrap Plan (Conservative)

- Workspace: `/root/RALF/.ralf-host`
- Runtime dir: `/root/RALF/.ralf-host/runtime`
- Tool readiness: `partial`

## Required Tools
- bash: present (/usr/bin/bash)
- curl: present (/usr/bin/curl)
- git: present (/usr/bin/git)
- tar: present (/usr/bin/tar)
- sha256sum: present (/usr/bin/sha256sum)

## Optional Tools (for future phases)
- minisign: missing
- lxc: missing
- pct: present (/usr/sbin/pct)
- tofu: missing
- terragrunt: missing
- ansible: missing

## Next Actions (not executed by host adapter)
- Install missing optional tools as needed for local execution (e.g. tofu, terragrunt, ansible, minisign)
- Populate `/root/RALF/.ralf-host/runtime/secrets` with environment/secrets files before local runner usage
- Add/choose a host-mode runner workflow
