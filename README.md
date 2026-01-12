# RALF Homelab (Bootstrap Repo)

Dieses Repository ist die **Source of Truth** für den Aufbau eines Homelab-Systems,
in dem ein zukünftiges System („RALF“) Dienste **planbar, genehmigungsfähig, reproduzierbar**
und **selbstheilend** ausrollen kann.

Aktueller Bootstrap-Stand:
- Remote: GitHub (temporär)
- Runner: Semaphore (wird zuerst installiert)
- Danach: PostgreSQL (Functional) → Gitea (extern via otta.zone) → Repo-Remote umstellen
- Alles läuft in **LXC** unter Proxmox, keine Docker-Deployments.

## Grundprinzipien (nicht verhandelbar)
- Netzwerk ist die Basis: ohne „Network Health“ keine Deployments
- Änderungen passieren kontrolliert: **Intent → Plan → Freigabe → Change**
- Jede Änderung ist rollback-fähig (Snapshots)
- Secrets gehören nicht ins Repo (Semaphore Variablen/Secrets)

## Struktur
- `docs/` – Grundgesetze (z.B. Netzwerk-Baseline)
- `healthchecks/` – bindende Checklisten (Gatekeeper)
- `plans/` – Intents & Pläne (Templates + konkrete Artefakte)
- `changes/` – Changes (Templates + konkrete Artefakte)
- `incidents/` – Störungen, Ursachen, Lessons Learned
- `services/` – Service-Steckbriefe
- `iac/` – Infrastructure as Code (OpenTofu + ggf. Ansible)
- `pipelines/` – Runner-Pipelines (Semaphore)
- `tests/` – Smoke/Acceptance-Tests (Teil der Definition of Done)

## Bootstrap Ablauf (kurz)
1. Semaphore wird als LXC „seeded“ (einmalig)
2. Semaphore zieht dieses Repo und führt Bootstrap-Jobs aus (Smoke/Toolchain)
3. Semaphore deployed PostgreSQL (Functional)
4. Semaphore deployed Gitea (extern: `gitea.otta.zone`)
5. Repo wird nach Gitea migriert, Semaphore Repo-URL umgestellt
6. Ab dann: Alles läuft intern (GitHub optional abschalten)

## Zonen
Zonen sind Flags (keine eigenen Netze):
- Playground: Lernen/Experimente, darf „brechen“
- Functional: muss stabil laufen

Siehe: `docs/network-baseline.md`
