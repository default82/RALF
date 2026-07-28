# ZIELBILD.md

Stand: 2026-07-28

Diese Datei ist die dauerhaft gepflegte Arbeitsgrundlage für Menschen und Coding-Agenten, die RALF entwickeln. Sie enthält Ziele, verbindliche Anweisungen, Entscheidungen, Grenzen und deren Status. Sie enthält keine vollständigen Überlegungen, Gesprächsprotokolle oder ausführlichen Alternativdiskussionen.

## Pflegevorgaben

- Vor jeder Entwicklungsaufgabe vollständig lesen.
- Bei Änderungen an Ziel, Anweisung, Entscheidung, Grenze, Meilenstein oder Definition of Done im selben Arbeitsschritt aktualisieren.
- Einträge nicht löschen, wenn sie abgeschlossen, ersetzt oder verworfen wurden.
- Status ändern und das Ergebnis knapp festhalten.
- Neue Einträge erhalten eine stabile Kennung.
- Unverbindliche Ideen ausdrücklich als `OFFEN` oder `IDEE` kennzeichnen.

## Statuswerte

- `AKTIV`: jetzt umzusetzen oder verbindlich zu beachten
- `SPAETER`: beschlossen, aber nicht Teil des aktuellen Meilensteins
- `OFFEN`: noch nicht entschieden
- `IDEE`: mögliche Richtung ohne Beschluss
- `ABGESCHLOSSEN`: umgesetzt oder erledigt
- `ERSETZT`: durch einen neueren Eintrag abgelöst
- `VERWORFEN`: bewusst nicht weiterverfolgt

# 1. Übergeordnetes Zielbild

| ID | Status | Ziel oder Anweisung |
|---|---|---|
| Z-001 | SPAETER | RALF soll ein anpassbarer lokaler KI-Assistent für unterschiedliche Nutzer und Einsatzzwecke werden, nicht nur für eine einzelne Person oder ein einzelnes Homelab. |
| Z-002 | SPAETER | RALF soll auf einfacher Hardware nutzbar sein und keine leistungsstarke lokale GPU als allgemeine Voraussetzung erzwingen. |
| Z-003 | SPAETER | RALF soll vorhandene Infrastruktur einbinden können und niemanden zwingen, ein neues Homelab aufzubauen oder bereits vorhandene Dienste doppelt zu betreiben. |
| Z-004 | SPAETER | Konkrete Produkte sollen langfristig austauschbar sein. RALF soll beispielsweise eine benötigte Speicher- oder Suchfähigkeit ansprechen können, ohne im Kern fest an PostgreSQL, MariaDB, MSSQL, pgvector oder Qdrant gebunden zu sein. |
| Z-005 | SPAETER | RALF soll langfristig auf mehreren Linux-basierten Zielplattformen bereitgestellt werden können. Proxmox, Docker und TrueNAS sind vorgesehene Zielumgebungen. |
| Z-006 | OFFEN | Native Windows-Server-Unterstützung ist nicht beschlossen. WSL2 oder eine Linux-VM können später als Windows-naher Betriebsweg geprüft werden. |
| Z-007 | SPAETER | Größere Dienste und Komponenten sollen später außerhalb eines kleinen RALF-Kerns isoliert betrieben werden können, auf Proxmox bevorzugt in eigenen LXC-Containern. |
| Z-008 | SPAETER | Ein kleiner Kern darf SQLite und eine kleine Weboberfläche enthalten. Ein umfangreiches Administrationsinterface mit Zugriff auf alle Funktionen und Adapter soll später eine getrennte Komponente sein. |
| Z-009 | SPAETER | Die Installation soll langfristig durch einen wachsenden Entscheidungs- und Abhängigkeitsgraphen sowie einen Fragenkatalog beschrieben werden können. |
| Z-010 | IDEE | Eine KI kann später den Installationsdialog führen und Nutzerwünsche in eine strukturierte Zielkonfiguration übersetzen. Validierung und Ausführung sollen dennoch auf nachvollziehbaren Regeln beruhen. |
| Z-011 | IDEE | Das Skill-Konzept von Hermes beziehungsweise vergleichbare offene Skill-Formate sollen als Inspiration für erweiterbare und selbst erstellbare Fähigkeiten geprüft werden. Es ist nicht entschieden, Hermes als Kern oder Abhängigkeit zu verwenden. |
| Z-012 | OFFEN | Die Rolle von MCP für externe Anbindungen oder interne ausgelagerte Komponenten ist noch nicht entschieden. MCP ist derzeit keine verbindliche Grundlage der Architektur. |

# 2. Aktueller Meilenstein: RALF Standalone 0.0.1

## Ziel

Eine feste und reproduzierbare erste Installation soll auf der vorhandenen Proxmox-Umgebung einen benutzbaren RALF-Ausgangspunkt bereitstellen. Dieser Stand dient zum praktischen Lernen und legt den späteren `ralf-core` noch nicht fest.

| ID | Status | Ziel oder Anweisung |
|---|---|---|
| M-001 | AKTIV | Zielplattform des ersten Deployments ist Proxmox VE. |
| M-002 | AKTIV | Der Installer erzeugt genau einen unprivilegierten LXC-Container. |
| M-003 | AKTIV | Modelllaufzeit, ein fest ausgewähltes Modell und eine kleine Weboberfläche werden zunächst gemeinsam in diesem Container installiert. |
| M-004 | AKTIV | Daten, Modell-Dateien und Konfiguration dürfen zunächst lokal und persistent im selben Container gespeichert werden. |
| M-005 | AKTIV | SQLite darf im Container verwendet werden, wenn die ausgewählte Weboberfläche oder eine andere Komponente es benötigt. |
| M-006 | AKTIV | Betriebssystem, Modelllaufzeit, Modell und Weboberfläche dürfen für diese Referenzinstallation fest vorgegeben werden. |
| M-007 | AKTIV | Noch keine automatische Hardwareerkennung, RAM- oder Speicherplatzdimensionierung, Benchmarklogik oder dynamische Modellauswahl implementieren. |
| M-008 | AKTIV | Noch keine allgemeine Multi-Plattform-, Datenbank-, Adapter-, MCP- oder Provider-Architektur implementieren, sofern sie für diesen Meilenstein nicht zwingend erforderlich ist. |
| M-009 | AKTIV | Die erste Installation wird als `RALF Standalone` behandelt und nicht vorschnell als endgültiger `ralf-core` definiert. |
| M-010 | AKTIV | Der Installationsweg muss aus einem definierten Ausgangszustand reproduzierbar sein. |
| M-011 | AKTIV | Installationsfehler müssen verständlich gemeldet werden. Bestehende Container, VMs, Storages und Netzwerke dürfen nicht stillschweigend verändert oder überschrieben werden. |
| M-012 | AKTIV | Zugangsdaten, Tokens und andere Geheimnisse dürfen nicht in das Repository gelangen. |

## Definition of Done

| ID | Status | Prüfkriterium |
|---|---|---|
| D-001 | AKTIV | Der Installationsweg erstellt den vorgesehenen unprivilegierten LXC auf Proxmox. |
| D-002 | AKTIV | Die kleine Weboberfläche ist nach der Installation erreichbar. |
| D-003 | AKTIV | Das installierte Modell beantwortet über die Weboberfläche eine Testanfrage. |
| D-004 | AKTIV | Notwendige Daten und Konfiguration überleben einen Container-Neustart. |
| D-005 | AKTIV | Die benötigten Prozesse starten nach einem Container-Neustart selbstständig. |
| D-006 | AKTIV | Die Installation kann aus dem dokumentierten Ausgangszustand erneut reproduziert werden. |
| D-007 | AKTIV | Der Installationsweg und die grundlegende Bedienung sind im Repository dokumentiert. |

# 3. Unmittelbar offene Entscheidungen

Diese Entscheidungen sind als Nächstes notwendig, bevor der Installer implementiert werden kann.

| ID | Status | Offene Entscheidung |
|---|---|---|
| O-001 | OFFEN | Linux-Distribution und Version des ersten LXC festlegen. |
| O-002 | OFFEN | Modelllaufzeit festlegen. |
| O-003 | OFFEN | Erstes Referenzmodell festlegen. |
| O-004 | OFFEN | Kleine Weboberfläche festlegen. |
| O-005 | OFFEN | Installationsform festlegen, beispielsweise ein vom Proxmox-Host gestartetes Bootstrap-Skript. |
| O-006 | OFFEN | Benennung, Netzwerkvorgaben und grundlegende persistente Verzeichnisse des ersten Containers festlegen. |

# 4. Abgeschlossene Anweisungen und Entscheidungen

| ID | Status | Ergebnis |
|---|---|---|
| A-001 | ABGESCHLOSSEN | Das GitHub-Repository `default82/RALF` wurde leer vorgefunden und als neues Projekt initialisiert. |
| A-002 | ABGESCHLOSSEN | `README.md`, `AGENTS.md`, `ZIELBILD.md` und eine Projektlizenz wurden als erste Repository-Grundlage vorgesehen. |
| A-003 | ABGESCHLOSSEN | Der erste praktische Schritt wurde von einer vollständigen Plattformarchitektur auf eine feste Proxmox-Standalone-Installation reduziert. |
| A-004 | ABGESCHLOSSEN | Eine endgültige Definition des RALF-Kerns wurde bewusst auf einen späteren Zeitpunkt verschoben. |
