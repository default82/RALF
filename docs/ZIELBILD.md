# RALF – Zielbild

Version 1.2 – Kanonisch (MVP)

## 1. Zweck

RALF betreibt ein Proxmox-Homelab reproduzierbar, kontrolliert und dokumentiert.

RALF ist:

- Orchestrator
- Entscheidungsstütze
- Dokumentationsinstanz

RALF ist nicht:

- autonomer Executor ohne Freigabe
- Blackbox
- Docker-zentriert

## 2. Leitplanken

- Plattform: Proxmox
- Betriebsform: LXC-first
- Netzwerk: `10.10.0.0/16`
- Gatekeeping: `OK | Warnung | Blocker`
- Priorität: Stabilität vor Geschwindigkeit

## 3. Basisdienste (Foundation)

1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore
5. Vaultwarden
6. Prometheus
7. n8n
8. KI-Instanz (lokal)

## 4. Verbindliche Bootstrap-Phasen

### Phase 0 – Vorbereitung

- Eingaben, Netz, IDs, Ressourcen prüfen
- Secrets-Quellen prüfen
- Start nur bei `OK` oder bewusst bestätigter `Warnung`

### Phase 1 – Foundation Core

- MinIO deployen und State/Artefakt-Pfad aktivieren
- PostgreSQL deployen und Basiszugriff prüfen
- Gitea deployen und internes kanonisches Remote bereitstellen
- Semaphore deployen und Templates/Runpfade seeden

### Phase 2 – Foundation Services

- Vaultwarden deployen
- Prometheus deployen
- Foundation-Smokes vollständig ausführen

### Phase 3 – Erweiterung

- n8n und KI-Dienste ausrollen
- weitere Domänen (z. B. Kommunikation) nur nach Gates

### Phase 4 – Betriebsmodus

- Semaphore-first als Standardbetrieb
- jeder Change mit Gate-Status und Nachweis
- Drift-/Health-Checks regelmäßig durchführen

## 5. Done-Kriterien je Phase

Eine Phase gilt nur als abgeschlossen, wenn:

- definierte Dienste laufen
- Smoke/Verify erfolgreich sind
- Gate-Status dokumentiert ist
- Artefakte abgelegt sind

## 6. Langfristige Richtung

RALF entwickelt sich zu einem kontrollierten Infrastruktur-Betriebssystem für das Homelab:

- lernfähig
- nachvollziehbar
- revisionsfest
- freigabegeführt
