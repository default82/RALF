# RALF Bootstrap Architektur

Stand: 2026-02-28 (Europe/Berlin)

## Leitplanken

- LXC-first, kein Docker.
- Jeder Schritt liefert `ok`, `warn` oder `blocker` inkl. kurzer Summary.
- Gitea ist kanonische Wahrheit (Single Source of Truth), GitHub nur Distribution.
- Bootstrap darf starten, aber nicht blind durchlaufen.
- Primaere Domain: `otta.zone` (kein internes `homelab.lan` noetig).

## Zielbild (One-Entry Bootstrap)

Ein Einstieg (One-liner) fuehrt reproduzierbar bis zum Zustand "RALF steht":

1. Preflight checks
2. Plan-Artefakte erzeugen
3. Kontrollierte Ausfuehrung (Default mit Bestaetigung)
4. Foundation deployen:
   - PostgreSQL
   - Gitea
   - Semaphore
   - Prometheus
   - Vaultwarden
5. Repo-Seed und Handover nach Gitea
6. Erweiterung deployen:
   - n8n
   - KI-Komponenten (Exo + LLM)
7. Proof-Deployment: MinIO via Semaphore (OpenTofu + Ansible)
8. Bootstrap-LXC als obsolete markieren, stoppen, Loeschkommando ausgeben

## Zwei-Stufen-Modell

### Stufe A: Seed (ultraklein)

- Konfiguration lesen (`env`, `answers.yml`, optional TUI)
- Preflight ausfuehren
- Runner-Bundle holen
- Integritaet pruefen (`sha256` oder `minisign`)
- Runner im Bootstrap-LXC starten

### Stufe B: Runner (im Bootstrap-LXC)

- Workspace + `outputs/` initialisieren
- Bootstrap-Repo initial von GitHub klonen
- Konfiguration mergen und finalisieren
- Plan erzeugen (IPs, CTIDs, Ressourcen)
- Gatekeeping erzwingen
- Foundation erstellen/konfigurieren/verifizieren
- Gitea/Semaphore initialisieren
- Canonical Remote auf Gitea umschalten

## Phasenmodell mit Checkpoints

- Checkpoint A: Probe/Preflight
- Checkpoint B: Plan/Gate
- Checkpoint C: Apply (Provisionierung)
- Checkpoint D: Configure/Verify/Handover

Alle Checkpoints schreiben nach `outputs/checkpoints.json`.

## Netzwerk- und ID-Konventionen

- Basisnetz: `10.10.0.0/16`
- Bootstrap-Netz (temporaer): `10.10.250.0/24`
- Funktionsgruppen:
  - `10` Hardware/Hosts
  - `20` Datenbanken
  - `30` Backup/Sicherheit
  - `40` Web/Admin
  - `50` Directory/Auth
  - `60` Medien
  - `70` Dokumente/Wissen
  - `80` Monitoring/Logging
  - `90` KI/Datenverarbeitung
  - `100` Automatisierung/Steuerung
  - `110` Kommunikation
  - `120` Spiele
  - `200` funktionale VM-Reserve
  - `0` Netzwerk (Router/Switches)

CTID/VMID-Ableitung:

- Formel: `CTID = <octet3><octet4_padded_3>`
- Beispiele:
  - `10.10.20.10 -> 20010`
  - `10.10.40.10 -> 40010`
  - `10.10.100.20 -> 100020`

## Bootstrap-LXC Lifecycle

Der Bootstrap-Container ist explizit temporaer:

- Name z. B. `ralf-bootstrap-<timestamp>` oder `tmp-ralf-bootstrap`
- Metadaten/Tags:
  - `ralf.role=bootstrap`
  - `ralf.lifecycle=ephemeral`
  - `ralf.delete_ok=true`
- Abschlussverhalten:
  - Container stoppen
  - Loeschkommando nur anzeigen (manuelles Delete)

Pflichtartefakt:

- `outputs/cleanup_manifest.json` mit CTIDs/IPs, Ephemeral-Markierung, Cleanup-Empfehlungen

## Secrets- und DB-Policy

- Waehrend Bootstrap: `secrets.json` nur transient im Runner-Workspace
- SSH-Keys aus `/root/ralf-secrets`
- Nach Vaultwarden-Start: Secrets uebertragen und `secrets.json` loeschen
- Keine Klartext-Secrets ins Repo

DB-Konvention:

- PostgreSQL bevorzugt, wenn Dienst es unterstuetzt
- Naming:
  - Datenbank: `<service>_db`
  - User: `<service>_user`
- Fallback: MariaDB mit gleicher Namenskonvention
- Passwoerter mindestens 32 Zeichen

## Distribution und Handover

- GitHub (`ralf/bootstrap`) fuer Launcher, Doku, Beispiele, Releases/Signaturen
- Gitea ist intern kanonisch
- Nach erfolgreichem Gitea-Bootstrap wird das Canonical Remote auf Gitea umgestellt
