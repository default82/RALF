# RALF – Zielbild

## 1. Kernidee

RALF ist die Radnabe des Homelabs.

Alle Infrastruktur-, Automatisierungs- und Entscheidungsprozesse laufen strukturiert über ihn.

Er erzeugt Artefakte.
Er stößt kontrollierte Ausführungen an.
Er beobachtet Ergebnisse.
Er lernt.

---

## 2. Technisches Fundament

### Plattform
- Proxmox
- LXC-first
- VM nur bei technischer Notwendigkeit (z. B. GPU-Passthrough)

### Netzwerk
- 10.10.0.0/16
- CTID = letzte zwei Oktette der IP
- Segmentierung nach Funktionsgruppen

### Storage
- MinIO als State-Backend
- Git (Gitea) als Source of Truth
- PostgreSQL als Wissens- und Statusspeicher

---

## 3. Basisdienste (Initiale Säulen)

- PostgreSQL
- Gitea
- Semaphore (Bootstrap-Container wird Semaphore)
- MinIO
- Vaultwarden
- Prometheus
- KI-Instanz (lokal)
- n8n

Diese Dienste bilden das stabile Fundament.

---

## 4. Betriebsmodell

RALF arbeitet als:

- Hub, nicht Pipeline
- Orchestrator, nicht Executor
- Dokumentierer, nicht Blackbox

---

## 5. Entwicklungsziel

RALF soll:

1. selbstständig einen Dienst vorschlagen
2. dessen Ressourcen prüfen
3. Artefakte erzeugen
4. Deployment vorbereiten
5. mit Freigabe ausführen
6. validieren
7. überwachen

Ab diesem Punkt steht RALF „auf eigenen Beinen“.

---

## 6. Langfristige Vision

Nach dem Bootstrap kann RALF selbständig orchestrieren:

- Matrix/Synapse
- Domainfreigaben in OPNsense
- weitere Dienste

RALF wird zu einem selbstreflektierenden, kontrollierten Infrastruktur-Betriebssystem.