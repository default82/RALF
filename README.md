# RALF

RALF ist ein frühes, gemeinschaftlich entwickeltes Projekt für einen anpassbaren lokalen KI-Assistenten. Das Projekt beginnt bewusst klein und praktisch: Zuerst entsteht eine reproduzierbare Standalone-Installation, die auf der vorhandenen Infrastruktur tatsächlich läuft. Die spätere Architektur wird aus den dabei gewonnenen Erfahrungen entwickelt und nicht vorab vollständig festgelegt.

RALF entsteht transparent durch Vibe Coding: Menschen geben Zielbild, Entscheidungen und Grenzen vor, während Coding-Agenten die Umsetzung in kleinen, überprüfbaren Schritten unterstützen.

## Aktueller Meilenstein

Der erste Meilenstein ist **RALF Standalone 0.0.1** für Proxmox VE:

- genau ein unprivilegierter LXC mit dem Namen `ralf-standalone`,
- `nesting=1` als feste Ubuntu-26.04-Betriebsanforderung im LXC,
- Ubuntu Server 26.04 LTS,
- ein dauerhaft betriebener, modellfreier Bootstrap als kleine Basis- und Statuskomponente,
- ein späteres kleines Webinterface für lokalen Status und regelbasierten Setup,
- Ollama, `qwen2.5-coder:7b` und Open WebUI nur als später auswählbare Komponenten beziehungsweise mögliches Referenzprofil,
- DHCP ohne vorausgesetzte Reservierung,
- persistente Daten im Root-Dateisystem des LXC,
- Installation durch ein vom Proxmox-Host gestartetes Bootstrap-Skript,
- Sicherung zunächst über normale Proxmox-Backups des LXC.

Diese Installation ist vorläufig **RALF Standalone** und noch nicht der endgültige `ralf-core`.

## Festgelegte Persistenzpfade

```text
/etc/ralf/             Konfiguration
/var/lib/ralf/ollama/  optionale lokale Modelllaufzeit und Modelle
/var/lib/ralf/webui/   optionale Weboberflächen-Daten und Datenbank
/var/log/ralf/         Installations- und Betriebsprotokolle
```

Der Bootstrap ist keine Wegwerfkomponente. Er bleibt nach der Erstinstallation als kleine, dauerhaft betriebene RALF-Basis bestehen und zeigt den allgemeinen Zustand, Inventar, gewünschte Fähigkeiten, Providerpräferenzen und einen regelbasiert erzeugten Zielplan. Ein umfangreiches Administrationsinterface und der spätere privilegierte Installer bleiben getrennte Komponenten.

Der Bootstrap benötigt kein Sprachmodell. Der Setup-Dialog wird zunächst durch einen deterministischen Fragen-, Entscheidungs- und Abhängigkeitsgraphen gesteuert und kann vollständig ohne Ollama, lokales Modell oder externe KI funktionieren. Eine KI-gestützte Gesprächsschicht kann später optional Nutzereingaben in eine strukturierte Zielkonfiguration übersetzen; Validierung, Abhängigkeitsauflösung und Installation bleiben regelbasiert.

Spätere Modellwege werden als Setup-Optionen behandelt: vorhandenen Modellserver verwenden, vorhandenen OpenAI-kompatiblen Endpunkt verwenden, lokalen Modellserver neu installieren, externen Modellanbieter konfigurieren oder zunächst ohne Modell fortfahren. Keiner dieser Wege ist Bestandteil des aktuellen Statusdienst-Grundgerüsts.

Vor jeder optionalen Installation gilt verbindlich Inventory-first: Der Bootstrap erfragt vorhandene Plattformen, Komponenten, Fähigkeiten und Provider, trennt Nutzerangaben von ausdrücklich read-only verifizierten Tatsachen und erzeugt daraus zunächst nur einen nachvollziehbaren Zielplan. Geeignete vorhandene Dienste werden gegenüber Neuinstallationen bevorzugt. Ohne abgeschlossene Bestandsaufnahme und ausdrückliche Planfreigabe werden weder Reverse Proxy, DNS-/Identitätskomponenten, Modellruntime und Modelle noch Datenbanken, Speicher-, Backup-, Monitoring-, Secrets- oder zusätzliche Webdienste installiert oder konfiguriert. RALF führt dafür keine ungefragten Netzwerkscans aus.

## Technische Grundlage des Bootstrap-Controllers

Das lokale Paket `ralf-bootstrap` 0.3.0 erweitert den Statusdienst um den produktneutralen Inventory-first-Controller und lokale Providerbewertungen. Python 3, Flask, Jinja und `sqlite3` genügen weiterhin; es gibt keine neue Runtime-Abhängigkeit. Die bestehende Statusoberfläche bietet unverändert `GET /`, `GET /healthz` und `GET /api/v1/status`. Der Controller ergänzt serverseitig gerenderte Seiten unter `/controller/` und ausschließlich lesende JSON-Endpunkte unter `/api/v1/controller/`.

Der Controller läuft im selben unprivilegierten Webprozess und darf ausschließlich seine explizit initialisierte lokale SQLite-Datenbank ändern. Er führt keine Paket-, systemd-, Proxmox-, OPNsense- oder Providermutationen aus und besitzt weder Netzwerkscan, Connector, externe Probe noch Shellausführung. VMID 100 verwendet weiterhin die installierte Statusversion `0.1.0`; Version `0.3.0` ist nur lokal implementiert und noch nicht dorthin ausgerollt.

### Lokale Entwicklung und Prüfung

Mit Python 3.12 oder neuer kann das Paket in einer virtuellen Umgebung installiert und getestet werden:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/pytest -q
```

Die Statusansicht ist über `GET /`, der technische Healthcheck über `GET /healthz` und der vollständige JSON-Status über `GET /api/v1/status` verfügbar. Für einen lokalen Gunicorn-Test wird ausschließlich Loopback verwendet:

```bash
.venv/bin/gunicorn --workers 1 --bind 127.0.0.1:8080 --no-control-socket ralf_bootstrap.wsgi:app
```

Die Controllerdatenbank wird weder beim Import noch beim Start automatisch angelegt. Für eine lokale Entwicklung erfolgt die Initialisierung ausdrücklich:

```bash
.venv/bin/python -m ralf_bootstrap.controller_db init --database /tmp/ralf-controller.db
```

Der Pfad muss in einem vorhandenen Verzeichnis liegen. Derselbe explizite Befehl migriert eine vorhandene Controllerdatenbank transaktional von Schema 1 auf Schema 2; Import, Flask-Start und Statusabruf migrieren niemals automatisch. Der Controller speichert Inventarzustände (`unknown`, `reported`, `verified`, `unavailable`, `conflict`, `declined`), Anforderungen, Providerpräferenzen, Abschnittsbestätigungen, Zielpläne, gehashte Einmal-CSRF-Tokens und inhaltsarme Auditereignisse. Planbestätigungen lösen keine Ausführung aus; jeder spätere infrastrukturelle Schritt benötigt einen neuen technischen Plan und eine eigene Apply-Freigabe.

### Read-only Verifikationsaufträge und Providerverträge

M-040 ergänzt versionierte Providerverträge, einzelne Claims und ausdrücklich zu bestätigende read-only Verifikationsumfänge. In diesem Stand können ausschließlich manuelle Beobachtungen und bereits extern erhobene, redigierte Evidenzzusammenfassungen bewertet werden. Rohkonfigurationen, Logs und Dateien werden nicht hochgeladen; Zugangsdaten, Tokens, private Schlüssel und Cookies sind unzulässig. Evidenz ist nach dem Speichern unveränderlich, kann nur durch einen neuen verknüpften Eintrag korrigiert werden und besitzt eine begrenzte Gültigkeit.

Die Oberfläche trennt drei Aussagen sichtbar: `Providerexistenz` bestätigt nur, dass der Provider vorhanden und grundsätzlich gesund ist; `Vertragskompatibilität` bewertet die nachgewiesenen Capability- und Sicherheitsclaims; `Integrationsbereitschaft` bewertet das konkrete Deployment. Ein Provider kann deshalb `verified` und `compatible`, aber wegen eines offenen Backendpfads weiterhin `blocked` sein. Veraltete Evidenz bleibt historisch erhalten, wird beim Lesen ohne versteckte Datenbankänderung als `stale` wirksam und erzeugt beim nächsten Plan erneut einen Verifikationsschritt.

Der erste Vertrag `secure-ingress.opnsense-caddy` modelliert OPNsense-Caddy ohne konkrete Adresse oder Zugangsdaten. Selbst nach vollständiger manueller Existenz- und Fähigkeitsbewertung bleibt die Integration durch O-012 blockiert, solange der sichere Backendpfad zum Loopback-Upstream nicht entschieden ist. Der Zielplan enthält dann `decide_integration` vor der späteren Wiederverwendung, aber weder einen Connectoraufruf noch eine lokale Caddy-Installation. Ein bestätigter Scope, eingetragene Evidenz und eine abgeschlossene Bewertung führen zu keiner technischen Providerprüfung und zu keinem Apply.

Der Webflow führt von Fragen und Inventar über Anforderungen, Verifikationsfreigaben und Providerpräferenzen zu vier eigenen „Diese Angaben sind korrekt“-Bestätigungen. Jede nachträgliche Änderung invalidiert betroffene Bestätigungen und vorhandene Pläne. Der deterministische Planer bevorzugt verifizierte oder gemeldete vorhandene Provider, weist offene Prüfungen und Konflikte aus und speichert keine Shellbefehle. Schreibende Formulare verwenden nur `POST`, POST/Redirect/GET und kurzlebige, formulargebundene Einmal-CSRF-Tokens; eine Benutzeranmeldung oder externe Proxyvertrauenskonfiguration ist noch nicht implementiert.

### Bestandsaufnahme und sicherer LAN-Zugang

Gunicorn bleibt dauerhaft ausschließlich auf `127.0.0.1:8080`. LAN-Zugang ist die optionale, austauschbare Fähigkeit `secure-ingress`; ihr konkreter Provider wird erst nach der Bestandsaufnahme gewählt. Ein geeigneter vorhandener Reverse Proxy wird gegenüber einem zusätzlichen lokalen Dienst bevorzugt. Ein lokaler Caddy im RALF-LXC ist nur ein möglicher späterer Fallback für Installationen ohne passenden vorhandenen Provider und derzeit nicht ausgewählt.

Inventare unterscheiden mindestens `unknown`, `reported`, `verified`, `unavailable`, `conflict` und `declined`. `reported` ist eine Nutzerangabe ohne technische Prüfung; `verified` setzt eine ausdrücklich freigegebene read-only Verifikation voraus. Fehlende Zugangsdaten oder eine abgelehnte Prüfung werden nicht durch Netzwerkscans umgangen.

Für die aktuelle Referenzumgebung ist deployment-spezifisch angegeben: Proxmox als Plattform, OPNsense als Firewall/Router und Caddy über das OPNsense-Plugin `os-caddy` als vorhandener Kandidat für `secure-ingress`. Diese Angaben haben derzeit den Zustand `reported`, nicht `verified`, und sind keine allgemeine Vorgabe für andere RALF-Installationen. Der sichere Backendpfad vom OPNsense-Caddy zum weiterhin nur auf Container-Loopback erreichbaren Statusdienst ist offen; insbesondere wird Port 8080 nicht stillschweigend im LAN geöffnet.

Der zugehörige Controller-Testfall erzeugt deshalb die Reihenfolge `verify_provider`, `decide_integration`, `reuse_provider`, markiert den offenen Backendvertrag als Blocker und erzeugt ausdrücklich keinen Schritt zur Installation eines lokalen Caddy. Der lokale Caddy bleibt lediglich ein nicht automatisch ausgewählter experimenteller Fallback im versionierten Providerkatalog.

Bis zur Providerentscheidung bleibt der Controller lokal beziehungsweise nur über einen ausdrücklich aufgebauten administrativen Tunnel erreichbar. In VMID 100 ist kein zusätzlicher LAN-Ingress installiert oder aktiviert. Es gibt weiterhin keine LAN-Freigabe, keine externe Providerverifikation, keinen Apply-Endpunkt und keine zusätzlichen Netzwerk-Capabilities.

Die direkten Laufzeitabhängigkeiten bleiben `Flask==3.1.3` und `Gunicorn==26.0.0`; die exakt geprüfte transitive Auflösung steht in [`requirements/runtime.lock`](requirements/runtime.lock). Für Tests werden ausschließlich `pytest==9.1.1` und `build==1.5.0` verwendet.

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

## Deployment des Statusdienstes

Der reproduzierbare Deploymentpfad prüft den laufenden Container, baut das aktuelle Wheel und zeigt die SHA-256-Prüfsummen aller übertragenen Artefakte:

```bash
sudo ./scripts/ralf-bootstrap-status-deploy.sh --plan --vmid 100
sudo ./scripts/ralf-bootstrap-status-deploy.sh --apply --vmid 100
```

Der allgemeine Fresh-Install-/Resume-Pfad baut nun Paketversion `0.3.0`. Er ist kein Upgradepfad für die in VMID 100 installierte Version `0.1.0` und wird in M-040 nicht gegen diesen Container ausgeführt. Ein späteres reales Controller-Upgrade ist M-041 und benötigt einen eigenen geprüften Plan sowie eine ausdrückliche Freigabe.

Vor dem Erzeugen einer Virtualenv prüft der Gastinstaller nicht nur das `venv`-Modul, sondern auch `ensurepip` und dessen eingebettete Pip-Version. Fehlt `ensurepip`, wird im Plan das aus dem Interpreter abgeleitete Paket (bei Python 3.14: `python3.14-venv`) samt Apt-Candidate angezeigt. Installiert wird ausschließlich dieses Paket; danach wird die Prüfung wiederholt.

Ein normaler `--apply` behandelt keine unvollständige Installation automatisch. Der nachgewiesene Teilzustand aus Benutzer/Gruppe, Bootstrap-Basisverzeichnis und genau einem fehlgeschlagenen temporären `.venv-build.*`-Verzeichnis ist ausschließlich über den ausdrücklich benannten Resume-Pfad behandelbar:

```bash
sudo ./scripts/ralf-bootstrap-status-deploy.sh --resume --vmid 100
sudo ./scripts/ralf-bootstrap-status-deploy.sh --resume --apply --vmid 100
```

Der Resume-Pfad validiert Bundle, Prüfsummen, Paketquellen, Locks und den exakten Teilzustand erneut. Er entfernt ausschließlich das eindeutig erkannte fehlgeschlagene temporäre Venv-Verzeichnis, installiert bei Bedarf das passende `pythonX.Y-venv`-Paket und setzt danach die reguläre Installation fort. Bei jeder anderen Teilinstallation wird ohne Änderung abgebrochen; es gibt keinen breiten Löschvorgang, keinen automatischen Rollback und keinen zweiten Versuch.

Virtuelle Umgebungen werden dabei niemals verschoben, kopiert oder per Shebang-Umschreibung repariert. Der reguläre Installationsweg erstellt `/opt/ralf/bootstrap/venv` direkt am endgültigen Zielpfad und verwendet bis zur vollständigen Prüfung die Markierung `.venv-install-in-progress`. Der ausdrücklich getrennte Reparaturpfad behandelt ausschließlich den real nachgewiesenen Zustand `recoverable_moved_venv_exec_failure`:

```bash
sudo ./scripts/ralf-bootstrap-status-deploy.sh --repair-venv --plan --vmid 100
sudo ./scripts/ralf-bootstrap-status-deploy.sh --repair-venv --apply --vmid 100
```

Nach einer neuen Freigabe stoppt dieser Pfad den Dienst, entfernt ausschließlich die exakt validierte endgültige Venv, legt `.venv-repair-in-progress` an, erstellt die Venv direkt am Zielpfad neu und prüft Shebangs, Pakete, Dienst und Loopback-Endpunkte. Benutzer, Gruppe, Bundle und Systempakete werden nicht erneut angelegt beziehungsweise übertragen; bei Fehlern bleiben Markierung und erreichte Zustand zur Diagnose erhalten. Ein normaler `--apply` oder `--resume` verweist bei diesem Zustand ausdrücklich auf `--repair-venv`.

Für den aktuell erreichten, durch die zu strenge Interpreterprüfung unterbrochenen Zustand verwendet der Reparaturpfad die Klassifikation `recoverable_venv_repair_validation_failure`. Eine POSIX-Venv darf `venv/bin/python` als Symlink auf den Basisinterpreter führen: Entscheidend sind `sys.prefix`, `sys.exec_prefix`, die Trennung von den Basispräfixen, `os.path.samefile(sys.executable, venv/bin/python)` und ein Venv-interner Paketpfad. In diesem Fortsetzungspfad wird die vorhandene Venv nicht gelöscht, neu erstellt oder erneut installiert. Nach einer neuen Freigabe werden ausschließlich Rechte finalisiert, die bestehende Unit geprüft, `reset-failed` und genau ein Dienststart ausgeführt; die Markierung und das Bundle werden erst nach erfolgreicher Endpunktprüfung entfernt.

Die vollständige Zustandsklassifikation liegt ausschließlich im Gastinstaller. Dessen read-only Modus `--classify --bundle /run/ralf-bootstrap-install` verwendet dieselben Prüfungen wie Plan und Apply und gibt auf stdout genau eine versionierte Zeile der Form `RALF_BOOTSTRAP_STATE_V1=<zustand>` aus. Bei `partial` erscheinen benannte Prädikate mit beobachtetem und erwartetem Wert ausschließlich auf stderr. Der Host validiert diese Schnittstelle strikt und baut keine zweite Installationsklassifikation nach; systemd wird dabei in einem kohärenten Snapshot gelesen und nur bei transienten Zuständen höchstens dreimal kurz read-only geprüft.

Bei `--apply` werden Wheel, Runtime-Lock, Konfiguration, systemd-Unit, Gast-Installationsskript und Prüfsummenmanifest ausschließlich nach `/run/ralf-bootstrap-install/` übertragen. Der Gastpfad richtet den unprivilegierten Benutzer, die Virtualenv und den Dienst `ralf-bootstrap.service` ein. Gunicorn verwendet den Einstiegspunkt `ralf_bootstrap.wsgi:app`, bindet ausschließlich an `127.0.0.1:8080` und startet mit bewusst deaktiviertem Control-Socket. Für die bereits vorhandenen read-only `ip`-Abfragen erlaubt die Unit zusätzlich `AF_NETLINK`; `AF_PACKET`, Netzwerk-Capabilities und öffentliche Bindungen bleiben ausgeschlossen. `/var/lib/ralf/bootstrap/state.db` wird in diesem Schritt nicht angelegt.

Zielpfade sind `/opt/ralf/bootstrap/{app,venv,VERSION}`, `/etc/ralf/bootstrap/config.toml` und `/var/lib/ralf/bootstrap/`. Ein zweiter Applylauf erkennt eine vollständige Installation und ersetzt keine Dateien. Die Runtime-Versionen sind exakt gepinnt und das Wheel sowie die Deploymentartefakte werden per SHA-256 geprüft. Die Runtime-Abhängigkeiten besitzen derzeit noch keine verpflichtenden Artefakt-Hashes; ein vollständig offline gehashtes Bundle ist eine spätere Erweiterung. Es gibt weiterhin keine LAN-Freigabe, Authentifizierung oder mutierenden Setup-Aktionen. VMID 100 verwendet die korrigierte Unit mit deaktiviertem Gunicorn-Control-Socket und read-only `AF_NETLINK`.

### Eng begrenztes Unit-Update

Für eine bereits vollständige Installation von `ralf-bootstrap` 0.1.0 steht ein getrennter Plan-/Apply-Pfad bereit:

```bash
sudo ./scripts/ralf-bootstrap-status-unit-update.sh --plan --vmid 100
sudo ./scripts/ralf-bootstrap-status-unit-update.sh --apply --vmid 100
```

Der Plan ist gegenüber dem Container vollständig read-only. Der Gast klassifiziert die Installation maschinenlesbar als `unit_update_required`, `unit_already_current` oder `unit_update_conflict`; der Host baut diese Klassifikation nicht nach. Zulässig ist ausschließlich der Übergang von der bestätigten alten Unit mit SHA-256 `8f5b30c7d9335824dfabb19cab5b338337860a45e785a6985370da9b8f6f48d7` zur Ziel-Unit mit genau zwei Änderungen: `--no-control-socket` und zusätzliches `AF_NETLINK`.

Ein Apply überträgt exakt `ralf-bootstrap.service`, `ralf-bootstrap-status-unit-update-guest.sh` und `SHA256SUMS` nach `/run/ralf-bootstrap-unit-update/`. Die Unit wird innerhalb von `/etc/systemd/system/` über eine validierte temporäre Datei atomar ersetzt; danach folgen höchstens ein `daemon-reload` und genau ein Dienstrestart. Anwendungscode, Wheel, Runtime-Lock, Virtualenv, Konfiguration, Benutzer und Daten werden vorher und nachher verglichen und nicht verändert. Bei Fehlern gibt es keinen automatischen Rollback und keinen zweiten Restart. Eine bereits aktuelle, gesunde Unit wird idempotent nur read-only geprüft.

Dieser Updatepfad wurde für den bestätigten M-035-Übergang in VMID 100 genau einmal erfolgreich ausgeführt. Unit, Dienstprozess, Journal, Loopback-Endpunkte, Netzwerkstatus und Härtung wurden anschließend read-only validiert; Anwendung, Venv, Konfiguration, Benutzer und Daten blieben unverändert. LAN-Bindung, Authentifizierung, TLS und zusätzliche Capabilities sind weiterhin ausgeschlossen.

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
sudo ./scripts/ralf-standalone-bootstrap.sh --plan
```

`--check` ist ein kompatibler Alias. Der Plan ermittelt die nächste freie VMID sowie Storage und Bridge nur dann automatisch, wenn jeweils genau eine geeignete Option vorhanden ist. Alternativ können `--vmid`, `--storage`, `--bridge`, `--cores`, `--memory`, `--swap` und `--disk` explizit gesetzt werden. Speicher und Swap werden in MiB, die Root-Disk in GiB angegeben. Ungültige, fehlende oder mehrdeutige Werte brechen ohne LXC-Änderung ab.

Die ausdrückliche Erstellung erfolgt erst mit `--apply`:

```bash
sudo ./scripts/ralf-standalone-bootstrap.sh --apply
```

`--apply` wiederholt den vollständigen Plan unmittelbar vor der Mutation, ruft genau einmal `pct create` auf und prüft die erzeugte LXC-Konfiguration anschließend read-only. Der Container bleibt gestoppt; Softwareinstallation, GPU-Passthrough und automatisches Rollback sind nicht Bestandteil dieses Schritts.

Der `pct create`-Aufruf setzt für die Ubuntu-26.04-Referenzinstallation fest `--features nesting=1`. Die Nachprüfung akzeptiert ausschließlich `features: nesting=1`; zusätzliche Features, Mountpoints oder GPU-Konfigurationen führen zum Fehler. Diese Einstellung ist keine allgemeine Anforderung späterer Betriebssysteme oder Plattformen.

## Ubuntu-Vorbereitung im Gast

Die kontrollierte Vorbereitung ist als separates Gastskript umgesetzt und wurde in VMID 100 bereits erfolgreich ausgeführt. Für weitere definierte Ausgangszustände stehen Plan- und Applymodus getrennt bereit:

```bash
./scripts/ralf-standalone-guest-prepare.sh --plan
./scripts/ralf-standalone-guest-prepare.sh --apply
```

`--plan` bleibt vollständig read-only. `--apply` prüft Ubuntu 26.04, amd64/x86_64, systemd, `systemd-networkd`, Netzwerk, DNS, Ubuntu-Paketquelle und den Paketstatus, führt anschließend nichtinteraktiv `apt-get update` sowie `apt-get full-upgrade` aus und legt danach ausschließlich die vier festgelegten RALF-Verzeichnisse mit `root:root` und Modus `0750` an. Ein erforderlicher Neustart wird nur gemeldet. Ollama, das Referenzmodell, Open WebUI, Docker, Podman, Datenbanken, GPU-Komponenten und weitere RALF-Software gehören nicht zu diesem Vorbereitungsschritt.

## Status

Der technische Ausgangszustand des dauerhaften Bootstraps ist erreicht: Der reale unprivilegierte LXC `ralf-standalone` (VMID 100) wurde erstellt, am 2026-08-01 nach Aktivierung von `nesting=1` kontrolliert neu gestartet und read-only validiert. Ubuntu 26.04 ist aktualisiert, Netzwerk und DHCP funktionieren, und die vier Basisverzeichnisse sind vorbereitet. Der Container enthält noch keine Modellruntime und kein Modell. Der Statusdienst `0.1.0` ist aktiviert, läuft unprivilegiert und antwortet ausschließlich über `127.0.0.1:8080`; `state.db` wurde nicht angelegt. Die korrigierte Unit läuft ohne Gunicorn-Control-Socket-Fehler und meldet dank `AF_NETLINK` den lokalen Netzwerkzustand korrekt als `configured`. D-002, M-035, M-039 und die lokale M-040-Implementierung sind erfüllt. M-041 ist der nächste Schritt für einen getrennt geplanten Controller-Upgradepfad; O-011 und O-012 sowie D-003 bis D-005 bleiben offen. Version `0.3.0` wurde noch nicht in VMID 100 installiert.

## Lizenz

RALF steht unter der Apache License 2.0. Siehe [`LICENSE`](LICENSE).
