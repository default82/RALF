# ADR-0001: No secrets in repo

## Status
Accepted

## Context
RALF wird Infrastruktur automatisiert ausrollen. Secrets im Git-Repo wären
ein dauerhafter Unfall (Leaks, Logs, Forks, CI, Backups).

## Decision
- Keine Secrets im Repo.
- Secrets werden ausschließlich als:
  - manuelle Eingabe (Bootstrap),
  - oder aus Secret-Store (später) bezogen.
- Repo enthält nur Templates/Beispiele (z. B. *.example).

## Consequences
- Setup braucht initialen Secret-Input.
- Wir planen später: age/sops oder Vault (noch offen).
