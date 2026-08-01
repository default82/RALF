# RALF

RALF ist ein frühes, gemeinschaftlich entwickeltes Projekt für einen anpassbaren lokalen KI-Assistenten. Das Projekt beginnt bewusst klein und praktisch: Zuerst entsteht eine reproduzierbare Standalone-Installation, die auf der vorhandenen Infrastruktur tatsächlich läuft. Die spätere Architektur wird aus den dabei gewonnenen Erfahrungen entwickelt und nicht vorab vollständig festgelegt.

RALF entsteht transparent durch Vibe Coding: Menschen geben Zielbild, Entscheidungen und Grenzen vor, während Coding-Agenten die Umsetzung in kleinen, überprüfbaren Schritten unterstützen.

## Aktueller Meilenstein

Der erste Meilenstein ist **RALF Standalone 0.0.1** für Proxmox VE:

- genau ein unprivilegierter LXC mit dem Namen `ralf-standalone`,
- `nesting=1` als feste Ubuntu-26.04-Betriebsanforderung im LXC,
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

Die kontrollierte Vorbereitung ist als separates Gastskript vorgesehen. Es wird später innerhalb des laufenden LXC ausgeführt; in VMID 100 wurde dieser Schritt noch nicht gestartet:

```bash
./scripts/ralf-standalone-guest-prepare.sh --plan
./scripts/ralf-standalone-guest-prepare.sh --apply
```

`--plan` bleibt vollständig read-only. `--apply` prüft Ubuntu 26.04, amd64/x86_64, systemd, `systemd-networkd`, Netzwerk, DNS, Ubuntu-Paketquelle und den Paketstatus, führt anschließend nichtinteraktiv `apt-get update` sowie `apt-get full-upgrade` aus und legt danach ausschließlich die vier festgelegten RALF-Verzeichnisse mit `root:root` und Modus `0750` an. Ein erforderlicher Neustart wird nur gemeldet. Ollama, das Referenzmodell, Open WebUI, Docker, Podman, Datenbanken, GPU-Komponenten und weitere RALF-Software gehören nicht zu diesem Vorbereitungsschritt.

## Status

Die grundlegenden Entscheidungen für RALF Standalone 0.0.1 sind abgeschlossen. Der reale unprivilegierte LXC `ralf-standalone` (VMID 100) wurde erstellt, am 2026-08-01 nach Aktivierung von `nesting=1` kontrolliert neu gestartet und read-only validiert. Er ist aktuell laufend, erhält sein Netzwerk per DHCP und enthält noch keine RALF-Software. Softwareinstallation und die übrigen Definition-of-Done-Punkte stehen noch aus.

## Lizenz

RALF steht unter der Apache License 2.0. Siehe [`LICENSE`](LICENSE).
