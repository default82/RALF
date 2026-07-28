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
| M-013 | AKTIV | Der erste LXC verwendet Ubuntu Server 26.04 LTS `Resolute Raccoon`. Für die Installation ist das aktuell verfügbare Proxmox-LXC-Template dieser Serie zu verwenden; anschließend sind alle verfügbaren Sicherheits- und Point-Updates einzuspielen. |
| M-014 | AKTIV | Ollama ist die festgelegte Modelllaufzeit für RALF Standalone 0.0.1. Ollama und das Referenzmodell werden im selben LXC wie die kleine Weboberfläche betrieben. |
| M-015 | AKTIV | `qwen2.5-coder:7b` ist das festgelegte Referenzmodell für RALF Standalone 0.0.1 und wird über Ollama im gemeinsamen LXC bereitgestellt. |
| M-016 | AKTIV | Open WebUI ist die festgelegte kleine Weboberfläche für RALF Standalone 0.0.1. Sie wird im gemeinsamen LXC betrieben und mit der lokalen Ollama-Instanz verbunden. |
| M-017 | AKTIV | Die Referenzinstallation wird durch ein auf dem Proxmox-Host gestartetes Bootstrap-Skript ausgeführt. Das Skript erstellt und konfiguriert den LXC und stößt anschließend die Installation und Einrichtung von Ubuntu-Aktualisierungen, Ollama, Referenzmodell und Open WebUI innerhalb des Containers an. |
| M-018 | AKTIV | Hostname und Proxmox-Bezeichnung des ersten LXC lauten `ralf-standalone`. |
| M-019 | AKTIV | Die Netzwerkkonfiguration des ersten LXC erfolgt grundsätzlich per DHCP. Für die erste Referenzinstallation wird keine feste IP-Adresse und keine DHCP-Reservierung vorausgesetzt. |
| M-020 | AKTIV | Für RALF Standalone 0.0.1 werden keine separaten Proxmox-Mountpoints eingerichtet. Persistente Daten liegen im Root-Dateisystem des LXC unter `/etc/ralf/`, `/var/lib/ralf/ollama/`, `/var/lib/ralf/webui/` und `/var/log/ralf/`. Die Sicherung erfolgt zunächst über normale Proxmox-Backups des LXC. |

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
| O-001 | ABGESCHLOSSEN | Als Betriebssystem des ersten LXC ist Ubuntu Server 26.04 LTS `Resolute Raccoon` festgelegt. Verwendet wird das aktuell verfügbare Proxmox-LXC-Template der Serie mit anschließenden Sicherheits- und Point-Updates. |
| O-002 | ABGESCHLOSSEN | Ollama ist als Modelllaufzeit für RALF Standalone 0.0.1 festgelegt. |
| O-003 | ABGESCHLOSSEN | `qwen2.5-coder:7b` ist als erstes Referenzmodell für RALF Standalone 0.0.1 festgelegt. |
| O-004 | ABGESCHLOSSEN | Open WebUI ist als kleine Weboberfläche für RALF Standalone 0.0.1 festgelegt. |
| O-005 | ABGESCHLOSSEN | Die Installation erfolgt durch ein vom Proxmox-Host gestartetes Bootstrap-Skript, das den LXC erstellt, konfiguriert und die Installation im Container anstößt. |
| O-006 | ABGESCHLOSSEN | Hostname und Proxmox-Bezeichnung lauten `ralf-standalone`. Die Netzwerkkonfiguration erfolgt per DHCP ohne vorausgesetzte Reservierung. Persistente Daten verbleiben ohne separate Proxmox-Mountpoints im Root-Dateisystem unter `/etc/ralf/`, `/var/lib/ralf/ollama/`, `/var/lib/ralf/webui/` und `/var/log/ralf/`; die Sicherung erfolgt zunächst über Proxmox-Backups des LXC. |

# 4. Abgeschlossene Anweisungen und Entscheidungen

| ID | Status | Ergebnis |
|---|---|---|
| A-001 | ABGESCHLOSSEN | Das GitHub-Repository `default82/RALF` wurde leer vorgefunden und als neues Projekt initialisiert. |
| A-002 | ABGESCHLOSSEN | `README.md`, `AGENTS.md`, `ZIELBILD.md` und `LICENSE` wurden als erste Repository-Grundlage angelegt. |
| A-003 | ABGESCHLOSSEN | Der erste praktische Schritt wurde von einer vollständigen Plattformarchitektur auf eine feste Proxmox-Standalone-Installation reduziert. |
| A-004 | ABGESCHLOSSEN | Eine endgültige Definition des RALF-Kerns wurde bewusst auf einen späteren Zeitpunkt verschoben. |
| A-005 | ABGESCHLOSSEN | Das Projekt wurde zunächst unter die Apache License 2.0 gestellt. |
| A-006 | ABGESCHLOSSEN | Ubuntu Server 26.04 LTS `Resolute Raccoon` wurde als Betriebssystem für den ersten RALF-Standalone-LXC festgelegt. |
| A-007 | ABGESCHLOSSEN | Ollama wurde als Modelllaufzeit für RALF Standalone 0.0.1 festgelegt. |
| A-008 | ABGESCHLOSSEN | `qwen2.5-coder:7b` wurde als Referenzmodell für RALF Standalone 0.0.1 festgelegt. |
| A-009 | ABGESCHLOSSEN | Open WebUI wurde als kleine Weboberfläche für RALF Standalone 0.0.1 festgelegt. |
| A-010 | ABGESCHLOSSEN | Ein vom Proxmox-Host gestartetes Bootstrap-Skript wurde als Installationsform für RALF Standalone 0.0.1 festgelegt. |
| A-011 | ABGESCHLOSSEN | `ralf-standalone` wurde als Hostname und Proxmox-Bezeichnung des ersten LXC festgelegt. |
| A-012 | ABGESCHLOSSEN | DHCP ohne vorausgesetzte Reservierung wurde als Netzwerkkonfiguration des ersten RALF-Standalone-LXC festgelegt. |
| A-013 | ABGESCHLOSSEN | Die persistenten Verzeichnisse des ersten LXC wurden festgelegt; separate Proxmox-Mountpoints werden in RALF Standalone 0.0.1 nicht verwendet. |

# 5. Verbindlicher Entwicklungsprozess

| ID | Status | Anweisung |
|---|---|---|
| P-001 | AKTIV | Nach jedem Arbeitsdurchlauf wird `Ergebnis.md` append-only um Ergebnis oder Fehler, Änderungen, Prüfungen, Blocker und nächsten Zielbild-Schritt ergänzt. Die zugehörigen Repository-Änderungen werden gezielt committed und auf den vorgesehenen Remote-Branch gepusht; technische Commit- oder Pushfehler werden wahrheitsgemäß nachgetragen. |
