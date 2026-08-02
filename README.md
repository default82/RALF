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

Der Bootstrap ist keine Wegwerfkomponente. Er bleibt nach der Erstinstallation als kleine, dauerhaft betriebene RALF-Basis bestehen und soll den allgemeinen Zustand, installierte und erreichbare Komponenten, offene Installations- oder Konfigurationsschritte sowie grundlegende Fehler und Warnungen anzeigen. Er stellt später den regelbasierten Setup-Dialog, nachvollziehbare Installationspläne und ausdrücklich freigegebene Einzelschritte bereit. Ein umfangreiches Administrationsinterface bleibt eine getrennte optionale Komponente.

Der Bootstrap benötigt kein Sprachmodell. Der Setup-Dialog wird zunächst durch einen deterministischen Fragen-, Entscheidungs- und Abhängigkeitsgraphen gesteuert und kann vollständig ohne Ollama, lokales Modell oder externe KI funktionieren. Eine KI-gestützte Gesprächsschicht kann später optional Nutzereingaben in eine strukturierte Zielkonfiguration übersetzen; Validierung, Abhängigkeitsauflösung und Installation bleiben regelbasiert.

Spätere Modellwege werden als Setup-Optionen behandelt: vorhandenen Modellserver verwenden, vorhandenen OpenAI-kompatiblen Endpunkt verwenden, lokalen Modellserver neu installieren, externen Modellanbieter konfigurieren oder zunächst ohne Modell fortfahren. Keiner dieser Wege ist Bestandteil des aktuellen Statusdienst-Grundgerüsts.

## Technische Grundlage des Statusdienstes

Das Grundgerüst des Bootstrap-Statusdienstes ist mit Python 3, Flask, Jinja, eingebettetem `sqlite3`, Gunicorn und systemd umgesetzt. Die read-only Oberfläche bietet `GET /`, `GET /healthz` und `GET /api/v1/status`, rendert lokale HTML-/CSS-Dateien und bindet in VMID 100 ausschließlich an `127.0.0.1:8080`. Sie ist damit nicht aus dem LAN erreichbar.

Der Dienst läuft unprivilegiert als `ralf-bootstrap` und führt keine Paket-, systemd- oder Proxmox-Mutationen aus. Das read-only Grundgerüst ist als installierbares Paket unter `src/ralf_bootstrap/` umgesetzt, benötigt kein Modell und keine Modellruntime und ist in VMID 100 als Version `0.1.0` installiert.

### Lokale Entwicklung und Prüfung

Mit Python 3.12 oder neuer kann das Paket in einer virtuellen Umgebung installiert und getestet werden:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/pytest -q
```

Die Statusansicht ist über `GET /`, der technische Healthcheck über `GET /healthz` und der vollständige JSON-Status über `GET /api/v1/status` verfügbar. Für einen lokalen Gunicorn-Test wird ausschließlich Loopback verwendet:

```bash
.venv/bin/gunicorn --workers 1 --bind 127.0.0.1:8080 ralf_bootstrap.wsgi:app
```

Der erste Dienst ist vollständig read-only: Er schreibt keine SQLite-Daten, installiert nichts und bietet keine mutierenden Aktionen, Authentifizierung, TLS- oder LAN-Freigabe. Der reale Dienst ist in VMID 100 aktiviert und lokal erreichbar; `state.db` bleibt nicht initialisiert.

Die direkten Laufzeitabhängigkeiten sind `Flask==3.1.3` und `Gunicorn==26.0.0`; die exakt geprüfte transitive Auflösung steht in [`requirements/runtime.lock`](requirements/runtime.lock). Für Tests werden ausschließlich `pytest==9.1.1` und `build==1.5.0` verwendet.

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

Bei `--apply` werden Wheel, Runtime-Lock, Konfiguration, systemd-Unit, Gast-Installationsskript und Prüfsummenmanifest ausschließlich nach `/run/ralf-bootstrap-install/` übertragen. Der Gastpfad richtet den unprivilegierten Benutzer, die Virtualenv und den Dienst `ralf-bootstrap.service` ein. Gunicorn verwendet den Einstiegspunkt `ralf_bootstrap.wsgi:app` und bindet ausschließlich an `127.0.0.1:8080`; `/var/lib/ralf/bootstrap/state.db` wird in diesem Schritt nicht angelegt.

Zielpfade sind `/opt/ralf/bootstrap/{app,venv,VERSION}`, `/etc/ralf/bootstrap/config.toml` und `/var/lib/ralf/bootstrap/`. Ein zweiter Applylauf erkennt eine vollständige Installation und ersetzt keine Dateien. Die Runtime-Versionen sind exakt gepinnt und das Wheel sowie die Deploymentartefakte werden per SHA-256 geprüft. Die Runtime-Abhängigkeiten besitzen derzeit noch keine verpflichtenden Artefakt-Hashes; ein vollständig offline gehashtes Bundle ist eine spätere Erweiterung. Es gibt weiterhin keine LAN-Freigabe, Authentifizierung oder mutierenden Setup-Aktionen. Der reale Reparatur-Apply hat die Venv-Rechte finalisiert und den Dienst erfolgreich gestartet. Offen bleiben ein nichtfataler Gunicorn-Control-Socket-Fehler beim Start und die durch die systemd-Härtung ohne `AF_NETLINK` blockierte lokale Netzwerkstatusermittlung.

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

Der technische Ausgangszustand des dauerhaften Bootstraps ist erreicht: Der reale unprivilegierte LXC `ralf-standalone` (VMID 100) wurde erstellt, am 2026-08-01 nach Aktivierung von `nesting=1` kontrolliert neu gestartet und read-only validiert. Ubuntu 26.04 ist aktualisiert, Netzwerk und DHCP funktionieren, und die vier Basisverzeichnisse sind vorbereitet. Der Container enthält noch keine Modellruntime und kein Modell. Der Statusdienst `0.1.0` ist aktiviert, läuft unprivilegiert und antwortet ausschließlich über `127.0.0.1:8080`; `state.db` wurde nicht angelegt. D-002 ist damit lokal erfüllt. Vor dem nächsten Funktionsausbau müssen der nichtfatale Gunicorn-Control-Socket-Fehler und die fehlerhafte Netzwerkstatusanzeige behoben werden. O-010 und O-011 sowie D-003 bis D-005 bleiben offen.

## Lizenz

RALF steht unter der Apache License 2.0. Siehe [`LICENSE`](LICENSE).
