# ZIELBILD.md

Stand: 2026-08-01

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
| M-003 | ERSETZT | Die frühere Vorgabe einer gemeinsamen Pflichtinstallation von Modelllaufzeit, Modell und Weboberfläche gilt nicht mehr. Nachfolger: M-027 und M-028. |
| M-004 | AKTIV | Daten und Konfiguration dürfen zunächst lokal und persistent im selben Container gespeichert werden; Modell-Dateien werden nur für später ausgewählte Modellkomponenten benötigt. |
| M-005 | AKTIV | SQLite darf im Container verwendet werden, wenn die ausgewählte Weboberfläche oder eine andere Komponente es benötigt. |
| M-006 | ERSETZT | Die frühere Festlegung von Betriebssystem, Modelllaufzeit, Modell und Weboberfläche als gemeinsames Referenzprofil ist nicht mehr Bootstrap-Voraussetzung. Nachfolger: M-027 und M-028. |
| M-007 | AKTIV | Noch keine automatische Hardwareerkennung, RAM- oder Speicherplatzdimensionierung, Benchmarklogik oder dynamische Modellauswahl implementieren. |
| M-008 | AKTIV | Noch keine allgemeine Multi-Plattform-, Datenbank-, Adapter-, MCP- oder Provider-Architektur implementieren, sofern sie für diesen Meilenstein nicht zwingend erforderlich ist. |
| M-009 | AKTIV | Die erste Installation wird als `RALF Standalone` behandelt und nicht vorschnell als endgültiger `ralf-core` definiert. |
| M-010 | AKTIV | Der Installationsweg muss aus einem definierten Ausgangszustand reproduzierbar sein. |
| M-011 | AKTIV | Installationsfehler müssen verständlich gemeldet werden. Bestehende Container, VMs, Storages und Netzwerke dürfen nicht stillschweigend verändert oder überschrieben werden. |
| M-012 | AKTIV | Zugangsdaten, Tokens und andere Geheimnisse dürfen nicht in das Repository gelangen. |
| M-013 | AKTIV | Der erste LXC verwendet Ubuntu Server 26.04 LTS `Resolute Raccoon`. Für die Installation ist das aktuell verfügbare Proxmox-LXC-Template dieser Serie zu verwenden; anschließend sind alle verfügbaren Sicherheits- und Point-Updates einzuspielen. |
| M-014 | SPAETER | Ollama bleibt eine mögliche lokale Modelllaufzeit und kann später durch den regelbasierten Setup-Dialog als Komponente ausgewählt werden. Sie ist keine Voraussetzung des Bootstraps. |
| M-015 | SPAETER | `qwen2.5-coder:7b` bleibt ein mögliches Referenzmodell für ein später ausgewähltes lokales Modellprofil. Es ist keine Voraussetzung des Bootstraps. |
| M-016 | SPAETER | Open WebUI bleibt eine mögliche spätere Weboberfläche für ein ausgewähltes Modellprofil. Sie ist keine Voraussetzung des modellfreien Bootstrap-Statusdienstes. |
| M-017 | ERSETZT | Der Host-Bootstrap bleibt die reproduzierbare Basis für Erstellung und Vorbereitung des LXC, stößt aber nicht mehr zwingend die Installation von Ollama, Referenzmodell oder Open WebUI an. Nachfolger: M-027 und M-028. |
| M-018 | AKTIV | Hostname und Proxmox-Bezeichnung des ersten LXC lauten `ralf-standalone`. |
| M-019 | AKTIV | Die Netzwerkkonfiguration des ersten LXC erfolgt grundsätzlich per DHCP. Für die erste Referenzinstallation wird keine feste IP-Adresse und keine DHCP-Reservierung vorausgesetzt. |
| M-020 | AKTIV | Für RALF Standalone 0.0.1 werden keine separaten Proxmox-Mountpoints eingerichtet. Bootstrap-Konfiguration und Statusdaten liegen zunächst im Root-Dateisystem; die vorbereiteten Pfade `/etc/ralf/`, `/var/lib/ralf/ollama/`, `/var/lib/ralf/webui/` und `/var/log/ralf/` stehen für den Bootstrap beziehungsweise später ausgewählte Komponenten bereit. Die Sicherung erfolgt zunächst über normale Proxmox-Backups des LXC. |
| M-021 | AKTIV | Die feste Referenzinstallation verwendet 4 CPU-Kerne, 12288 MiB RAM, 4096 MiB Swap und eine 40-GiB-Root-Disk. Diese Werte sind Referenzwerte der ersten Installation und keine allgemeinen Mindestanforderungen. VMID, Storage und Bridge werden standardmäßig sicher ermittelt; die Werte können über explizite CLI-Parameter überschrieben werden. |
| M-022 | AKTIV | Der Plan-/Preflight-Pfad validiert alle Ressourcenparameter und bricht bei ungültigen oder unvollständigen Angaben sowie bei nicht eindeutiger automatischer Storage- oder Bridge-Auswahl vor jeder LXC-Mutation mit verständlicher Ausgabe ab. Eine belegte VMID wird niemals überschrieben. |
| M-023 | AKTIV | `--apply` wiederholt den vollständigen Plan unmittelbar vor der Mutation, ruft genau einmal `pct create` für den unprivilegierten `ralf-standalone`-LXC auf und prüft die resultierende Konfiguration read-only. Der Container bleibt gestoppt; Softwareinstallation, GPU-Passthrough und automatisches Rollback sind nicht Bestandteil dieses Schritts. |
| M-024 | ABGESCHLOSSEN | VMID 100 wurde am 2026-08-01 mit der notwendigen Proxmox-Funktion `nesting=1` und genau einem `pct reboot 100 --timeout 120` kontrolliert neu gestartet. Die read-only Prüfung bestätigte wirksames `nesting=1`, aktive Netzwerkdienste, `eth0`/veth-Link, DHCP-IPv4, Default-Route, Gateway, DNS und HTTPS-Erreichbarkeit einer Ubuntu-Paketquelle. Die DHCP-Adresse bleibt dynamisch und ist keine dauerhafte Zusicherung. |
| M-025 | ABGESCHLOSSEN | Der Bootstrap erstellt die Ubuntu-26.04-Referenzinstallation von Anfang an mit `features: nesting=1` und prüft diese Einstellung nach `pct create` exakt. Diese Betriebsanforderung ist für systemd-Basisdienste im unprivilegierten Ubuntu-26.04-LXC nachgewiesen und gilt nicht als allgemeine Vorgabe für spätere Betriebssysteme oder Plattformen. |
| M-026 | ABGESCHLOSSEN | Das separate Gastskript prüft Ubuntu 26.04, amd64/x86_64, systemd, Netzwerk, DNS, Ubuntu-Paketquelle und dpkg, führt danach nichtinteraktiv `apt-get update` sowie `apt-get full-upgrade` aus und legt die vier festgelegten RALF-Basisverzeichnisse mit `root:root` und Modus `0750` idempotent an. Ein erforderlicher Neustart wird nur gemeldet; Ollama, Modell, Open WebUI, Docker, Podman, Datenbanken, GPU-Komponenten und weitere RALF-Software sind nicht Teil dieses Schritts. |
| M-027 | AKTIV | Der Bootstrap bleibt nach der Erstinstallation als kleine dauerhaft betriebene RALF-Basis bestehen und entwickelt sich zu einem modellfreien Status- und Basisverwaltungsdienst mit kleinem Webinterface. Die erste Version zeigt den lokalen Basiszustand, installierte und erreichbare Komponenten, offene Setup-Schritte sowie grundlegende Fehler und Warnungen. Ein umfangreiches Administrationsinterface bleibt getrennt und optional. |
| M-028 | AKTIV | Modellruntime, Modell und zusätzliche Weboberfläche sind spätere auswählbare Komponenten. Der regelbasierte Setup-Dialog muss später vorhandene Modellserver, OpenAI-kompatible Endpunkte, eine lokale Modellserver-Neuinstallation, externe Anbieter und einen zunächst modellfreien Betrieb abbilden können. Für den aktuellen Schritt wird keiner dieser Wege implementiert. |
| M-029 | ABGESCHLOSSEN | Das read-only Grundgerüst des dauerhaften Bootstrap- und Statusdienstes ist als installierbares Python-/Flask-Paket mit lokaler HTML-/CSS-Darstellung, Statusermittlung, `GET /`, `GET /healthz`, `GET /api/v1/status`, SQLite-Read-only-Kapselung und lokalen Tests umgesetzt. SQLite-Schreibvorgänge, Setup-Fragen, Installationsplanung, mutierende Aktionen, LAN-Freigabe, Authentifizierung, Modellzugriff, Ollama, Open WebUI, MCP und Adapterverwaltung bleiben außerhalb dieses Schritts. Eine reale Installation in VMID 100 ist nicht erfolgt. |
| M-030 | ABGESCHLOSSEN | Der reproduzierbare Host-/Gast-Deploymentpfad für das geprüfte Paket `ralf-bootstrap` ist mit SHA-256-geprüftem Bundle, direkt am endgültigen Zielpfad erstellter Virtualenv, exakten Runtime-Pins, unprivilegiertem Systembenutzer, Zielverzeichnissen und gehärteter systemd-Unit für `127.0.0.1:8080` implementiert und gemockt getestet. Eine reale Installation in VMID 100 ist noch nicht erfolgreich abgeschlossen; Runtime-Abhängigkeiten besitzen keine verpflichtenden Artefakt-Hashes. |
| M-031 | ABGESCHLOSSEN | Die Venv-Erkennung prüft `venv`, `ensurepip` und die eingebettete Pip-Version tatsächlich; das benötigte Paket wird strikt aus Python Major/Minor als `pythonX.Y-venv` ermittelt, per `apt-cache policy` gegen Ubuntu 26.04 geprüft und erst vor der Venv-Erstellung installiert. Der ausdrücklich benannte `--resume`-Pfad behandelt ausschließlich den nachgewiesenen Zustand `recoverable_venv_failure`, entfernt nur dessen eindeutig validiertes temporäres `.venv-build.*`-Verzeichnis und setzt die Installation ohne breiten Löschvorgang oder automatischen Rollback fort. Die reale Installation in VMID 100 bleibt bis zu einem neuen freigegebenen Resume-Lauf unvollständig. |
| M-032 | ABGESCHLOSSEN | Virtuelle Python-Umgebungen werden im RALF-Deployment nicht verschoben, kopiert, umbenannt oder per Shebang-Umschreibung repariert. Der reguläre Installationsweg erstellt die Venv direkt unter `/opt/ralf/bootstrap/venv` und schützt die Erstellung mit einer Installationsmarkierung. Der ausschließlich explizit aufrufbare Zustand `recoverable_moved_venv_exec_failure` erhält einen read-only Plan und einen eng begrenzten `--repair-venv`-Pfad mit Reparaturmarkierung, direkter Neuerstellung und nachgelagerter Dienstvalidierung. Die reale Installation in VMID 100 ist dadurch noch nicht erfolgreich abgeschlossen. |
| M-033 | ABGESCHLOSSEN | Die Venv-Interpreterprüfung berücksichtigt POSIX-Symlinks korrekt: `sys.prefix` und `sys.exec_prefix` müssen die erwartete Venv referenzieren, von den Basispräfixen getrennt sein, und `os.path.samefile(sys.executable, venv/bin/python)` sowie ein Venv-interner Paketpfad werden geprüft. Der unterbrochene Zustand `recoverable_venv_repair_validation_failure` ist eng klassifizierbar und kann ohne Venv-Löschung, Neuaufbau oder Paketinstallation ausschließlich durch Rechtefinalisierung, Unit-Prüfung, einmaligen Start und nachgelagerte Validierung fortgesetzt werden. Die reale Dienstinstallation in VMID 100 bleibt bis zu einer neuen Freigabe unvollständig. |

## Definition of Done

| ID | Status | Prüfkriterium |
|---|---|---|
| D-001 | ABGESCHLOSSEN | Der Installationsweg erstellte den vorgesehenen unprivilegierten LXC auf Proxmox als VMID 100 und die read-only Prüfung bestätigte die Zielkonfiguration. |
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
| O-002 | ERSETZT | Die frühere Festlegung von Ollama als verpflichtende Modelllaufzeit ist aufgehoben. Nachfolger: M-028 und A-020. |
| O-003 | ERSETZT | Die frühere Festlegung von `qwen2.5-coder:7b` als verpflichtendem Referenzmodell ist aufgehoben. Nachfolger: M-028 und A-020. |
| O-004 | ERSETZT | Die frühere Festlegung von Open WebUI als verpflichtender Weboberfläche ist aufgehoben. Nachfolger: M-028 und A-020. |
| O-005 | ABGESCHLOSSEN | Die Installation erfolgt durch ein vom Proxmox-Host gestartetes Bootstrap-Skript, das den LXC erstellt, konfiguriert und die Installation im Container anstößt. |
| O-006 | ABGESCHLOSSEN | Hostname und Proxmox-Bezeichnung lauten `ralf-standalone`. Die Netzwerkkonfiguration erfolgt per DHCP ohne vorausgesetzte Reservierung. Persistente Daten verbleiben ohne separate Proxmox-Mountpoints im Root-Dateisystem unter `/etc/ralf/`, `/var/lib/ralf/ollama/`, `/var/lib/ralf/webui/` und `/var/log/ralf/`; die Sicherung erfolgt zunächst über Proxmox-Backups des LXC. |
| O-007 | ABGESCHLOSSEN | Für die feste Referenzinstallation gelten 4 CPU-Kerne, 12288 MiB RAM, 4096 MiB Swap und 40 GiB Root-Disk. Die nächste freie VMID wird standardmäßig über Proxmox ermittelt; Storage und Bridge werden nur bei genau einer geeigneten Option automatisch gewählt. `--vmid`, `--storage`, `--bridge`, `--cores`, `--memory`, `--swap` und `--disk` überschreiben die Standardwerte beziehungsweise Auswahl. Mehrdeutige oder fehlende Optionen sowie ungültige Parameter brechen vor jeder Änderung ab. |
| O-008 | OFFEN | GPU-Unterstützung und insbesondere GPU-Passthrough für RALF Standalone sind nicht entschieden. Eine Umsetzung ist nicht Teil des aktuellen Meilensteins. |
| O-009 | ABGESCHLOSSEN | Der Bootstrap- und Statusdienst wird mit Python 3 aus Ubuntu 26.04, einer eigenen virtuellen Umgebung, Flask, Jinja, Python-`sqlite3`, Gunicorn und systemd umgesetzt. Die Darstellung nutzt lokale serverseitig gerenderte HTML-/CSS-Dateien ohne Node.js, npm, Frontend-Framework oder CDN. Der Dienst läuft als unprivilegierter Benutzer `ralf-bootstrap` über `ralf-bootstrap.service`, bindet zunächst ausschließlich an `127.0.0.1:8080` und verwendet `/opt/ralf/bootstrap/{app,venv,VERSION}`, `/etc/ralf/bootstrap/config.toml` sowie `/var/lib/ralf/bootstrap/state.db`. Ein kleines eigenes Storage-Modul kapselt spätere persistente SQLite-Daten. Der Webprozess bleibt read-only und führt keine Paket-, systemd- oder Proxmox-Mutationen aus; die erste Oberfläche umfasst `GET /`, `GET /healthz` und `GET /api/v1/status`. |
| O-010 | OFFEN | Wie wird das kleine Bootstrap-Webinterface sicher aus dem lokalen Netzwerk erreichbar? Zu berücksichtigen sind Authentifizierung, TLS oder ein vorhandener Reverse Proxy, zulässige Netzwerke, Host-Header-Prüfung, CSRF-Schutz bei späteren Formularen, sichere Setup-Tokens und die dynamische DHCP-Adresse. |
| O-011 | OFFEN | Wie kommuniziert der unprivilegierte Bootstrap-Webdienst später mit dem privilegierten regelbasierten Installer? Zu berücksichtigen sind ausdrückliche Nutzerfreigabe, validierter Installationsplan, erlaubte statt frei formulierter Befehle, klar begrenzte Rechte, nachvollziehbare Protokollierung und kein allgemeiner Root-Shell-Zugang. Eine IPC-, sudo-, Socket-, Queue- oder Helper-Technik wird noch nicht ausgewählt. |

# 4. Abgeschlossene Anweisungen und Entscheidungen

| ID | Status | Ergebnis |
|---|---|---|
| A-001 | ABGESCHLOSSEN | Das GitHub-Repository `default82/RALF` wurde leer vorgefunden und als neues Projekt initialisiert. |
| A-002 | ABGESCHLOSSEN | `README.md`, `AGENTS.md`, `ZIELBILD.md` und `LICENSE` wurden als erste Repository-Grundlage angelegt. |
| A-003 | ABGESCHLOSSEN | Der erste praktische Schritt wurde von einer vollständigen Plattformarchitektur auf eine feste Proxmox-Standalone-Installation reduziert. |
| A-004 | ABGESCHLOSSEN | Eine endgültige Definition des RALF-Kerns wurde bewusst auf einen späteren Zeitpunkt verschoben. |
| A-005 | ABGESCHLOSSEN | Das Projekt wurde zunächst unter die Apache License 2.0 gestellt. |
| A-006 | ABGESCHLOSSEN | Ubuntu Server 26.04 LTS `Resolute Raccoon` wurde als Betriebssystem für den ersten RALF-Standalone-LXC festgelegt. |
| A-007 | ERSETZT | Die frühere Pflichtentscheidung für Ollama wurde durch die optionale Komponentenauswahl ersetzt. Nachfolger: A-020. |
| A-008 | ERSETZT | Die frühere Pflichtentscheidung für `qwen2.5-coder:7b` wurde durch die optionale Komponentenauswahl ersetzt. Nachfolger: A-020. |
| A-009 | ERSETZT | Die frühere Pflichtentscheidung für Open WebUI wurde durch die optionale Komponentenauswahl ersetzt. Nachfolger: A-020. |
| A-010 | ABGESCHLOSSEN | Ein vom Proxmox-Host gestartetes Bootstrap-Skript wurde als Installationsform für RALF Standalone 0.0.1 festgelegt. |
| A-011 | ABGESCHLOSSEN | `ralf-standalone` wurde als Hostname und Proxmox-Bezeichnung des ersten LXC festgelegt. |
| A-012 | ABGESCHLOSSEN | DHCP ohne vorausgesetzte Reservierung wurde als Netzwerkkonfiguration des ersten RALF-Standalone-LXC festgelegt. |
| A-013 | ABGESCHLOSSEN | Die persistenten Verzeichnisse des ersten LXC wurden festgelegt; separate Proxmox-Mountpoints werden in RALF Standalone 0.0.1 nicht verwendet. |
| A-014 | ABGESCHLOSSEN | `GOAL.md` wurde als allgemeingültiger, wiederverwendbarer Arbeitsauftrag für Codex CLI angelegt und in den Projektdokumenten verankert. |
| A-015 | ABGESCHLOSSEN | Der erste reale `ralf-standalone`-LXC wurde am 2026-07-31 als VMID 100 erstellt und read-only geprüft. Er ist gestoppt und enthält noch keine RALF-Software. |
| A-016 | ABGESCHLOSSEN | Der erste kontrollierte Start von VMID 100 wurde am 2026-08-01 nach Aktivierung von `nesting=1` read-only validiert. Der laufende, weiterhin leere LXC erhält Netzwerk per DHCP; die Adresse ist nicht dauerhaft festgelegt. |
| A-017 | ABGESCHLOSSEN | Der reproduzierbare Bootstrap übergibt `--features nesting=1` beim einzigen `pct create`-Aufruf und lehnt nachträgliche oder zusätzliche LXC-Features in der read-only Konfigurationsprüfung ab. |
| A-018 | ABGESCHLOSSEN | Die Ubuntu-Vorbereitung ist als getrenntes Gastskript mit read-only `--plan` und mutierendem `--apply` umgesetzt. Vor Mutationen werden OS, Architektur, systemd, Netzwerk, DNS, Paketquelle und dpkg geprüft; nach der Aktualisierung werden ausschließlich die vier RALF-Basisverzeichnisse auf `root:root`/`0750` gesetzt. Ein Neustart wird nicht automatisch ausgeführt. |
| A-019 | ABGESCHLOSSEN | Der Bootstrap bleibt dauerhaft als kleine modellfreie RALF-Basis für Statusanzeige, regelbasierten Setup-Dialog, Installationsplan und ausdrücklich freigegebene Einzelschritte bestehen; ein großes Administrationsinterface bleibt getrennt und optional. |
| A-020 | ABGESCHLOSSEN | Ollama, `qwen2.5-coder:7b` und Open WebUI waren zunächst feste Bestandteile des Standalone-Plans und sind nun spätere auswählbare Komponenten. Der Bootstrap benötigt kein Modell; Fragen-, Entscheidungs- und Abhängigkeitsauflösung bleiben zunächst deterministisch und regelbasiert. |
| A-021 | ABGESCHLOSSEN | Der erreichte technische Ausgangszustand bleibt erhalten: VMID 100 ist ein laufender unprivilegierter Ubuntu-26.04-LXC mit `nesting=1`, funktionierendem Netzwerk, aktualisiertem Paketstand, vorbereiteten RALF-Basisverzeichnissen sowie reproduzierbaren Host- und Gastskripten. |
| A-022 | ABGESCHLOSSEN | O-009 wurde entschieden: Der dauerhafte Bootstrap bleibt eine kleine Python-3-/Flask-Anwendung mit Jinja, eingebettetem `sqlite3`, Gunicorn und systemd. Der erste Dienst läuft unprivilegiert, read-only und ausschließlich auf `127.0.0.1:8080`; Modellzugriff und mutierende Setup-Aktionen sind nicht Teil des Grundgerüsts. |
| A-023 | ABGESCHLOSSEN | M-029 wurde umgesetzt: Das lokale Paket `ralf-bootstrap` stellt ein read-only Statusmodell, die drei lokalen HTTP-Endpunkte, lokale Templates/CSS, SQLite-Read-only-Prüfung und automatisierte Tests bereit. Die Anwendung bleibt modellfrei, unprivilegiert vorgesehen und ausschließlich lokal testbar; VMID 100 wurde nicht verändert. |
| A-024 | ABGESCHLOSSEN | M-030 wurde umgesetzt: Host- und Gastskript übertragen ausschließlich das geprüfte Wheel, Runtime-Lock, Konfiguration, systemd-Unit, Installationsskript und SHA-256-Manifest, richten die Installation idempotent ein und aktivieren ausschließlich den Loopback-Dienst. Der Pfad wurde nur mit Mocks getestet; VMID 100 blieb unverändert. |
| A-025 | ABGESCHLOSSEN | Die nach dem fehlgeschlagenen Erstlauf nachgewiesene Ursache war ein verfügbares `venv`-Modul ohne `ensurepip`. M-031 ergänzt die echte Ensurepip-Prüfung, die präzise Paketermittlung und den ausschließlich für `recoverable_venv_failure` zulässigen Resume-Modus; VMID 100 wurde in diesem Arbeitsdurchlauf nicht verändert. |
| A-026 | ABGESCHLOSSEN | Der reale Resume-Apply erzeugte eine verschobene Venv, deren absolute Console-Shebangs auf den entfernten `.venv-build.WydEtv`-Pfad zeigten und `ralf-bootstrap.service` mit `203/EXEC` scheitern ließen. M-032 korrigiert die reguläre Erstellung auf den endgültigen Pfad und ergänzt den ausschließlich expliziten `recoverable_moved_venv_exec_failure`-/`--repair-venv`-Pfad; VMID 100 wurde in diesem Arbeitsdurchlauf nicht verändert. |
| A-027 | ABGESCHLOSSEN | Die fehlerhafte Pfadcontainment-Prüfung für `sys.executable` wurde durch eine symlink-taugliche Präfix-, `samefile`- und Paketpfadprüfung ersetzt. Der Zustand `recoverable_venv_repair_validation_failure` bleibt während Dienst- und Endpunktprüfung markiert; sein expliziter Fortsetzungspfad verändert nur Venv-Rechte, setzt den systemd-Fehlerzustand zurück, startet den bereits aktivierten Dienst genau einmal und entfernt Markierung/Bundle erst nach Erfolg. Ein realer Apply ist weiterhin nicht ausgeführt. |

# 5. Verbindlicher Entwicklungsprozess

| ID | Status | Anweisung |
|---|---|---|
| P-001 | AKTIV | Nach jedem Arbeitsdurchlauf wird `Ergebnis.md` append-only um Ergebnis oder Fehler, Änderungen, Prüfungen, Blocker und nächsten Zielbild-Schritt ergänzt. Die zugehörigen Repository-Änderungen werden gezielt committed und auf den vorgesehenen Remote-Branch gepusht; technische Commit- oder Pushfehler werden wahrheitsgemäß nachgetragen. |
| P-002 | AKTIV | Vor jedem Codex-Arbeitsdurchlauf sind `AGENTS.md`, `GOAL.md` und `ZIELBILD.md` vollständig sowie die jüngsten relevanten Einträge in `Ergebnis.md` zu lesen. `GOAL.md` bleibt allgemein; die konkrete nächste Aufgabe wird aus dem aktuellen Zielbild abgeleitet. |
