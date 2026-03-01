# RALF – Zielbild

Version 1.1 – Kanonisch

## 1. Kernidee

RALF ist die Radnabe des Homelabs.

Alle Infrastruktur-, Automatisierungs- und Entscheidungsprozesse laufen strukturiert über RALF:

- Artefakte erzeugen
- kontrolliert ausführen
- Ergebnisse validieren
- Lernen dokumentieren

## 2. Geltungsbereich und Nicht-Ziele

### Geltungsbereich

- Betrieb eines lokalen Homelabs auf Proxmox
- Infrastruktur-Orchestrierung für LXC-basierte Dienste
- nachvollziehbarer Übergang in einen stabilen Semaphore-first-Betrieb

### Nicht-Ziele

- kein autonomes Self-Deployment ohne Freigabe
- kein blindes Internet-Exposing
- kein Docker-basierter Primärbetrieb

## 3. Technisches Fundament

### Plattform

- Proxmox
- LXC-first
- VM nur bei technischer Notwendigkeit (z. B. GPU/Passthrough)

### Netzwerk

- Primärnetz: `10.10.0.0/16`
- Segmentierung nach Funktionsgruppen
- CTID-Ableitung aus dem Adressschema

### Persistenz & Source of Truth

- MinIO: State-/Artefakt-Storage
- Gitea: kanonische Git-Quelle (intern)
- PostgreSQL: Status-, Wissens- und Ereignisspeicher

## 4. Basisdienste (Initiale Säulen)

- MinIO
- PostgreSQL
- Gitea
- Semaphore
<<<<<<< HEAD
=======
- MinIO
>>>>>>> f200d596326529e49fcd13e611cc042e296ea1ba
- Vaultwarden
- Prometheus
- n8n
- KI-Instanz (lokal)

Diese Dienste bilden das stabile Fundament.

## 5. Zielreihenfolge für den Bootstrap

1. MinIO bereitstellen (Remote-State/Artefakte)
2. PostgreSQL bereitstellen (gemeinsame Datenbasis)
3. Gitea bereitstellen (internes kanonisches Remote)
4. Semaphore bereitstellen und seeden
5. Foundation validieren, danach Erweiterungswellen ausrollen

## 6. Betriebsmodell

RALF arbeitet als:

- Hub, nicht Pipeline
- Orchestrator, nicht Executor
- Dokumentierer, nicht Blackbox

Jeder Schritt endet in einem Gate-Status:

- OK
- Warnung
- Blocker

## 7. Qualitätsziele

- Stabilität vor Geschwindigkeit
- Nachvollziehbarkeit vor Autonomie
- Reproduzierbarkeit vor Komfort
- konservative Ressourcenplanung

## 8. Entwicklungsziel

RALF soll:

1. Dienste vorschlagen
2. Ressourcen und Risiken prüfen
3. Artefakte erzeugen
4. Deployment vorbereiten
5. mit Freigabe ausführen
6. validieren und überwachen
7. Verbesserungen aus Betriebserfahrungen ableiten

## 9. Langfristige Vision

<<<<<<< HEAD
Nach dem Bootstrap kann RALF kontrolliert weitere Domänen orchestrieren (z. B. Kommunikation, KI, Integrationen), ohne seine Governance-Prinzipien zu brechen.
=======
---

## 6. Langfristige Vision

Nach dem Bootstrap kann RALF selbständig orchestrieren:

- Matrix/Synapse
- Domainfreigaben in OPNsense
- weitere Dienste

RALF wird zu einem selbstreflektierenden, kontrollierten Infrastruktur-Betriebssystem.
>>>>>>> f200d596326529e49fcd13e611cc042e296ea1ba
