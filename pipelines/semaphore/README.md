# Semaphore Pipelines

Dieser Ordner beschreibt Pipeline-Templates/Blueprints für Semaphore.

## Ziel
- Bootstrap: Repo checkout + Smoke + Toolchain
- Später: `tofu init/plan/apply` + Tests + Doku-Update

## Bootstrap
Der Bootstrap ist bewusst simpel:
1. Repo pull/checkout
2. Smoke-Test
3. Toolchain installieren/prüfen

Erst danach werden produktive Stacks angewendet.

## Migration GitHub → Gitea
Die Pipeline bleibt gleich. Nur die Repo-URL wird in Semaphore geändert:
- von GitHub URL
- auf `gitea.otta.zone` URL
