# Network Baseline – RALF Homelab

## Ziel
Dieses Dokument definiert das Netzwerk als verbindliche Grundlage
für alle Deployments, Automatisierungen und Entscheidungen durch RALF.

# Network Baseline – RALF Homelab

## Ziel
Dieses Dokument definiert das Netzwerk als verbindliche Grundlage
für alle Deployments, Automatisierungen und Entscheidungen durch RALF.

Ohne grünes Netzwerk findet kein Deploy statt.

---

## Authority
- Zentrale Instanz: OPNsense
- Management: https://10.10.0.1:8443

---

## Adressraum
- Gesamtnetz: 10.10.0.0/16
- Statische IPs
- Keine DHCP-Ausnahmen

---

## IP-Semantik (3. Oktett)

| Bereich | Bedeutung |
|------:|-----------|
| 0 | Core / OPNsense |
| 10 | Netzwerk-Infrastruktur |
| 20 | Datenbanken |
| 30 | Backup & Sicherheit |
| 40 | Web & Admin |
| 50 | Verzeichnisdienste |
| 60 | Medien |
| 70 | Dokumentation & Wissen |
| 80 | Monitoring & Logging |
| 90 | KI & Datenverarbeitung |
| 100 | Automatisierung |
| 110 | Medien & Downloader |
| 200 | Funktionale Sonderfälle |

---

## Zonen (Flags)
- Playground: Experimente, Lernen, Umbauten
- Functional: Muss stabil laufen

Zonen sind **logische Flags**, keine eigenen Netze.

---

## DNS & DHCP
- DNS: OPNsense
- DHCP: OPNsense
- Keine weiteren DNS/DHCP-Instanzen erlaubt

---

## Reverse Proxy
- Caddy läuft auf OPNsense
- Publishing erfolgt ausschließlich dort

---

## Gatekeeper-Regel
Wenn die Network Health Checklist nicht vollständig grün ist:
- keine Deploys
- keine Änderungen
- nur Analyse & Heilung

---

## Network Health Checklist (verbindlich)

Die technische und operative Gesundheit des Netzwerks wird durch die
**Network Health Checklist** definiert.

Referenz:
- Datei: `healthchecks/network-health.yml`

Die Checklist ist **bindend** für alle Deployments und Änderungen.

### Durchsetzungsregel
- Wenn **ein** Check als `blocker` markiert ist und fehlschlägt:
  - ❌ keine Deployments
  - ❌ keine Konfigurationsänderungen
  - ✅ erlaubt sind nur:
    - Analyse
    - Dokumentation
    - Heilungsmaßnahmen
    - Rollback

Diese Regel gilt für:
- manuelle Änderungen
- automatisierte Änderungen
- zukünftige autonome Aktionen von RALF

---

## Änderungsprinzip
- Jede Netzwerkänderung erzeugt ein Artefakt
- Jede Änderung ist rollback-fähig
