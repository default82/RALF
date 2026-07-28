# RALF

RALF ist ein frühes, gemeinschaftlich entwickeltes Projekt für einen anpassbaren lokalen KI-Assistenten. Das Projekt beginnt bewusst klein und praktisch: Zuerst entsteht eine reproduzierbare Standalone-Installation, die auf der vorhandenen Infrastruktur tatsächlich läuft. Die spätere Architektur wird aus den dabei gewonnenen Erfahrungen entwickelt und nicht vorab vollständig festgelegt.

RALF entsteht transparent durch Vibe Coding: Menschen geben Zielbild, Entscheidungen und Grenzen vor, während Coding-Agenten die Umsetzung in kleinen, überprüfbaren Schritten unterstützen.

## Aktueller Meilenstein

Der erste Meilenstein ist **RALF Standalone 0.0.1** für Proxmox VE:

- genau ein unprivilegierter LXC mit dem Namen `ralf-standalone`,
- Ubuntu Server 26.04 LTS,
- Ollama als Modelllaufzeit,
- `qwen2.5-coder:7b` als Referenzmodell,
- Open WebUI als kleine Weboberfläche,
- DHCP ohne vorausgesetzte Reservierung,
- persistente Daten im Root-Dateisystem des LXC,
- Installation durch ein vom Proxmox-Host gestartetes Bootstrap-Skript,
- Sicherung zunächst über normale Proxmox-Backups des LXC.

Diese Installation ist vorläufig **RALF Standalone** und noch nicht der endgültige `ralf-core`.

## Festgelegte Persistenzpfade

```text
/etc/ralf/             Konfiguration
/var/lib/ralf/ollama/  Modelle und Ollama-Daten
/var/lib/ralf/webui/   Open-WebUI-Daten und Datenbank
/var/log/ralf/         Installations- und Betriebsprotokolle
```

## Langfristige Richtung

RALF soll später:

- für unterschiedliche Nutzer und Einsatzzwecke anpassbar sein,
- auf einfacher Hardware starten können,
- vorhandene Infrastruktur einbinden, statt neue Dienste oder ein neues Homelab zu erzwingen,
- konkrete Produkte wie PostgreSQL, MSSQL, MariaDB oder Qdrant austauschbar anbinden können,
- neben Proxmox langfristig auch andere Linux-basierte Zielplattformen wie Docker und TrueNAS unterstützen,
- größere Komponenten außerhalb eines kleinen Kerns isolieren können,
- Fähigkeiten und selbst erstellbare Skills schrittweise erweitern können.

Diese Punkte sind Zielrichtung, nicht bereits implementierte Architektur.

## Projektdokumente

- [`AGENTS.md`](AGENTS.md) enthält verbindliche Arbeitsregeln für Codex CLI und andere Coding-Agenten.
- [`GOAL.md`](GOAL.md) enthält den allgemeingültigen, wiederverwendbaren Arbeitsauftrag für Codex CLI.
- [`ZIELBILD.md`](ZIELBILD.md) ist die fortlaufend gepflegte Quelle für Ziele, Anweisungen, Entscheidungen und deren Status.
- [`Ergebnis.md`](Ergebnis.md) protokolliert Ergebnisse und Fehler der einzelnen Arbeitsdurchläufe append-only.
- [`LICENSE`](LICENSE) enthält die Projektlizenz.

## Arbeiten mit Codex CLI

Codex soll vor jeder Änderung `AGENTS.md`, `GOAL.md` und `ZIELBILD.md` vollständig lesen sowie die jüngsten relevanten Einträge in `Ergebnis.md` berücksichtigen. Der allgemeine Auftrag bleibt unverändert; die konkrete nächste Aufgabe ergibt sich aus dem aktuellen Zielbild.

Jeder Arbeitsdurchlauf umfasst einen kleinen überprüfbaren Schritt, relevante Prüfungen, notwendige Dokumentationspflege, einen neuen Eintrag in `Ergebnis.md`, einen gezielten Commit und einen Push auf den vorgesehenen Remote-Branch.

## Bootstrap-Preflight

Der erste ungefährliche Teil des Proxmox-Bootstraps prüft ausschließlich die Voraussetzungen und verändert keine Container oder Hostkonfigurationen:

```bash
sudo ./scripts/ralf-standalone-bootstrap.sh --check
```

Der Preflight erwartet einen Proxmox-Host, prüft die benötigten Proxmox-Befehle, sucht im Templatekatalog nach Ubuntu 26.04 und bricht ab, falls bereits ein LXC namens `ralf-standalone` existiert. Die eigentliche Container-Erstellung ist noch nicht implementiert.

## Status

Die grundlegenden Entscheidungen für RALF Standalone 0.0.1 sind abgeschlossen. Implementiert ist bislang nur der read-only Bootstrap-Preflight; Container-Erstellung, Softwareinstallation und vollständige Definition of Done stehen noch aus.

## Lizenz

RALF steht unter der Apache License 2.0. Siehe [`LICENSE`](LICENSE).