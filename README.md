# RALF

RALF ist ein frühes, gemeinschaftlich entwickeltes Projekt für einen anpassbaren lokalen KI-Assistenten. Das Projekt beginnt bewusst klein und praktisch: Zuerst soll eine reproduzierbare Standalone-Installation entstehen, die auf der vorhandenen Infrastruktur tatsächlich läuft. Die spätere Architektur wird aus den dabei gewonnenen Erfahrungen entwickelt und nicht vorab vollständig festgelegt.

RALF entsteht transparent durch Vibe Coding: Menschen geben Zielbild, Entscheidungen und Grenzen vor, während Coding-Agenten die Umsetzung in kleinen, überprüfbaren Schritten unterstützen.

## Aktueller Meilenstein

Der erste Meilenstein ist eine feste Referenzinstallation für Proxmox:

- ein unprivilegierter LXC-Container,
- ein fest ausgewähltes lokales Sprachmodell samt Laufzeit,
- eine kleine Weboberfläche,
- lokale persistente Speicherung innerhalb dieses Containers,
- ein reproduzierbarer Installationsweg,
- ein erfolgreicher Funktionstest nach Installation und Neustart.

Diese Installation ist vorläufig **RALF Standalone** und noch nicht der endgültige `ralf-core`.

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
- [`ZIELBILD.md`](ZIELBILD.md) ist die fortlaufend gepflegte Quelle für Ziele, Anweisungen, Entscheidungen und deren Status.
- [`Ergebnis.md`](Ergebnis.md) protokolliert die Ergebnisse und Fehler der einzelnen Arbeitsdurchläufe.
- [`LICENSE`](LICENSE) enthält die Projektlizenz.

## Arbeiten mit Codex CLI

Codex soll vor jeder Änderung zuerst `AGENTS.md` und `ZIELBILD.md` lesen. Änderungen, die Ziele, Grenzen, Entscheidungen oder den Stand eines Meilensteins verändern, müssen gleichzeitig in `ZIELBILD.md` nachgeführt werden. Codex verwendet dafür die konventionelle Projektdatei `AGENTS.md`, wie sie auch vom Codex-Initialisierungsworkflow erzeugt wird.

## Bootstrap-Preflight

Der erste ungefährliche Teil des Proxmox-Bootstraps prüft ausschließlich die Voraussetzungen und verändert keine Container oder Hostkonfigurationen:

```bash
sudo ./scripts/ralf-standalone-bootstrap.sh --check
```

Der Preflight erwartet einen Proxmox-Host, prüft die benötigten Proxmox-Befehle, sucht im Templatekatalog nach Ubuntu 26.04 und bricht ab, falls bereits ein LXC namens `ralf-standalone` existiert. Die eigentliche Container-Erstellung ist noch nicht implementiert.

## Status

Das Repository befindet sich in der Initialisierung. Die Referenzkomponenten sind im Zielbild festgelegt; implementiert ist bislang nur der read-only Bootstrap-Preflight, noch keine Container-Erstellung oder Softwareinstallation.

## Lizenz

RALF steht unter der Apache License 2.0. Siehe [`LICENSE`](LICENSE).
