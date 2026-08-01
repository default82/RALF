# Ergebnisprotokoll

Diese Datei wird nach jedem Arbeitsdurchlauf erweitert. Bestehende Einträge bleiben unverändert.

## 2026-07-28 – Laufprotokoll verbindlich eingeführt

- Bearbeitete Zielbild-ID: P-001
- Ergebnis: Ein append-only Ergebnisprotokoll sowie die Pflicht zu gezieltem Commit und Push nach jedem Arbeitsdurchlauf wurden als dauerhafte Arbeitsregel eingeführt.
- Geänderte Dateien: `AGENTS.md`, `ZIELBILD.md`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente vollständig gelesen; Git-Status und Remote geprüft; Dokumentationsdiff und Geheimnisausschluss werden vor dem Commit geprüft.
- Nicht ausgeführte Prüfungen: Keine Code-, Installations- oder Infrastrukturtests, da ausschließlich Projektdokumentation geändert wurde.
- Risiken oder Blocker: Die fachliche Implementierung von RALF bleibt durch O-001 bis O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-001
- Veröffentlichung: Dieser Eintrag wird gemeinsam mit den zugehörigen Änderungen committed und auf einen Remote-Branch gepusht.

## 2026-07-28 – Pull Request 1 gemergt

- Bearbeitete Zielbild-ID: P-001
- Ergebnis: Pull Request #1 wurde aus dem Draft-Status genommen, auf Merge-Fähigkeit geprüft und per Squash nach `main` gemergt.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: PR-Status und Merge-Fähigkeit über GitHub geprüft; für den Head-Commit waren keine Statuschecks gemeldet; lokaler `main` wurde anschließend per Fast-forward mit `origin/main` abgeglichen.
- Nicht ausgeführte Prüfungen: Keine erneuten Code- oder Infrastrukturtests, da ausschließlich der bereits dokumentationsgeprüfte Pull Request veröffentlicht wurde.
- Risiken oder Blocker: Die fachliche Implementierung von RALF bleibt durch O-001 bis O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-001
- Veröffentlichung: Der Merge erzeugte Commit `4583b3950a0ed10acf250b1cd54811375a87e754`; dieser Protokolleintrag wird separat auf `main` gepusht.

## 2026-07-28 – Ubuntu Server 26.04 LTS festgelegt

- Bearbeitete Zielbild-IDs: O-001, M-013, A-006
- Ergebnis: Ubuntu Server 26.04 LTS `Resolute Raccoon` wurde verbindlich als Betriebssystem des ersten RALF-Standalone-LXC festgelegt. Der Installer soll das aktuell verfügbare Proxmox-LXC-Template dieser Serie verwenden und danach alle verfügbaren Sicherheits- und Point-Updates einspielen.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Die aktuelle Ubuntu-Server-LTS wurde anhand offizieller Ubuntu-Quellen geprüft; Zielbild-ID, Status und Folgeentscheidung wurden auf Konsistenz geprüft.
- Nicht ausgeführte Prüfungen: Keine Code-, Installations- oder Infrastrukturtests, da ausschließlich eine Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Die konkrete Verfügbarkeit und exakte Bezeichnung des Ubuntu-26.04-LXC-Templates auf dem Ziel-Proxmox-Host muss bei der Implementierung geprüft werden. Die Implementierung bleibt durch O-002 bis O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-002
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Ollama als Modelllaufzeit festgelegt

- Bearbeitete Zielbild-IDs: O-002, M-014, A-007
- Ergebnis: Ollama wurde verbindlich als Modelllaufzeit für RALF Standalone 0.0.1 festgelegt. Ollama und das noch auszuwählende Referenzmodell werden im selben LXC wie die kleine Weboberfläche betrieben.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Status, Folgeentscheidung und Übereinstimmung mit dem aktuellen Ein-Container-Meilenstein wurden geprüft.
- Nicht ausgeführte Prüfungen: Keine Code-, Installations- oder Infrastrukturtests, da ausschließlich eine Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Modell, Weboberfläche, Installationsform sowie Container- und Netzwerkvorgaben sind noch offen. Die Implementierung bleibt durch O-003 bis O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-003
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Qwen-Coder-Referenzmodell festgelegt

- Bearbeitete Zielbild-IDs: O-003, M-015, A-008
- Ergebnis: `qwen2.5-coder:7b` wurde verbindlich als Referenzmodell für RALF Standalone 0.0.1 festgelegt und soll über Ollama im gemeinsamen LXC bereitgestellt werden.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Modellbezeichnung, Statusübergang und Übereinstimmung mit der festgelegten Ollama-Laufzeit wurden geprüft.
- Nicht ausgeführte Prüfungen: Das Modell wurde noch nicht heruntergeladen, gestartet oder auf der Zielhardware getestet, da bislang ausschließlich die Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Der Ollama-Modelltag kann sich langfristig auf ein anderes Artefakt beziehen; die bei der Implementierung tatsächlich aufgelöste Modellversion sollte nachvollziehbar protokolliert werden. Die Implementierung bleibt durch O-004 bis O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-004
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Open WebUI als Weboberfläche festgelegt

- Bearbeitete Zielbild-IDs: O-004, M-016, A-009
- Ergebnis: Open WebUI wurde verbindlich als kleine Weboberfläche für RALF Standalone 0.0.1 festgelegt. Open WebUI wird im gemeinsamen LXC betrieben und mit der lokalen Ollama-Instanz verbunden.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Statusübergang, Folgeentscheidung und Übereinstimmung mit dem aktuellen Ein-Container-Meilenstein wurden geprüft.
- Nicht ausgeführte Prüfungen: Open WebUI wurde noch nicht installiert, gestartet oder mit Ollama verbunden, da bislang ausschließlich die Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Die konkrete Installationsart und Versionsbindung von Open WebUI sind im Rahmen der Implementierung noch festzulegen. Die Implementierung bleibt durch O-005 und O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-005
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Bootstrap-Skript als Installationsform festgelegt

- Bearbeitete Zielbild-IDs: O-005, M-017, A-010
- Ergebnis: Die Referenzinstallation wird durch ein auf dem Proxmox-Host gestartetes Bootstrap-Skript ausgeführt. Das Skript erstellt und konfiguriert den unprivilegierten LXC und stößt danach die Installation und Einrichtung von Ubuntu-Aktualisierungen, Ollama, `qwen2.5-coder:7b` und Open WebUI im Container an.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Statusübergang, Übereinstimmung mit dem Proxmox-LXC-Meilenstein und Abgrenzung zur noch offenen Container- und Netzwerkkonfiguration wurden geprüft.
- Nicht ausgeführte Prüfungen: Es wurde noch kein Bootstrap-Skript implementiert oder auf einem Proxmox-Host ausgeführt, da ausschließlich die Installationsform beschlossen wurde.
- Risiken oder Blocker: Containername, Netzwerkvorgaben und persistente Verzeichnisse sind noch offen. Die Implementierung bleibt durch O-006 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-006
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Standalone-Container benannt

- Bearbeitete Zielbild-IDs: O-006, M-018, A-011
- Ergebnis: `ralf-standalone` wurde verbindlich als Hostname und Proxmox-Bezeichnung des ersten RALF-Standalone-LXC festgelegt. O-006 bleibt für Netzwerkvorgaben und persistente Verzeichnisse offen.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Bezeichnung, Status und Abgrenzung der weiterhin offenen Teile von O-006 wurden auf Konsistenz geprüft.
- Nicht ausgeführte Prüfungen: Kein Container wurde erstellt oder umbenannt, da ausschließlich eine Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Netzwerkvorgaben und persistente Verzeichnisse sind weiterhin offen. Die Implementierung bleibt dadurch blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-006 – Netzwerkvorgabe
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – DHCP als Netzwerkvorgabe festgelegt

- Bearbeitete Zielbild-IDs: O-006, M-019, A-012
- Ergebnis: Der erste `ralf-standalone`-LXC bezieht seine Netzwerkkonfiguration grundsätzlich per DHCP. Für die Referenzinstallation werden weder eine feste IP-Adresse noch eine DHCP-Reservierung vorausgesetzt.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Die Netzwerkentscheidung wurde auf Übereinstimmung mit dem einfachen und infrastrukturoffenen Bootstrap-Ziel geprüft; O-006 wurde für die noch offenen persistenten Verzeichnisse offen gelassen.
- Nicht ausgeführte Prüfungen: Es wurde kein LXC erstellt und keine DHCP-Zuweisung getestet, da ausschließlich eine Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Die per DHCP vergebene Adresse kann sich ändern und muss nach der Installation zuverlässig ermittelt und ausgegeben werden. Die grundlegenden persistenten Verzeichnisse sind weiterhin offen.
- Nächster sinnvoller Zielbild-Eintrag: O-006 – persistente Verzeichnisse
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Persistenzpfade des Standalone-LXC festgelegt

- Bearbeitete Zielbild-IDs: O-006, M-020, A-013
- Ergebnis: RALF Standalone 0.0.1 verwendet keine separaten Proxmox-Mountpoints. Konfiguration, Ollama-Daten, Open-WebUI-Daten und Protokolle liegen persistent im Root-Dateisystem des LXC unter `/etc/ralf/`, `/var/lib/ralf/ollama/`, `/var/lib/ralf/webui/` und `/var/log/ralf/`. Die Sicherung erfolgt zunächst über normale Proxmox-Backups des LXC.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Pfade, Statusübergang und Übereinstimmung mit dem Ein-Container-Meilenstein sowie der vorhandenen Definition of Done wurden geprüft.
- Nicht ausgeführte Prüfungen: Die Verzeichnisse wurden noch nicht erstellt, beschrieben oder durch ein Proxmox-Backup gesichert, da ausschließlich eine Projektentscheidung dokumentiert wurde.
- Risiken oder Blocker: Die tatsächlichen Datenpfade von Ollama und Open WebUI müssen bei der Implementierung gezielt auf die festgelegten RALF-Pfade konfiguriert oder nachvollziehbar dorthin gebunden werden.
- Nächster sinnvoller Zielbild-Eintrag: Implementierung des Bootstrap-Skripts für RALF Standalone 0.0.1.
- Veröffentlichung: Die Dokumentationsänderungen wurden direkt auf `main` committed.

## 2026-07-28 – Read-only Bootstrap-Preflight implementiert

- Bearbeitete Zielbild-IDs: M-001, M-010, M-011, M-012, M-013, M-017, P-001
- Ergebnis: Das Host-Bootstrap-Skript besitzt einen ausschließlich lesenden `--check`-Modus. Er prüft Root-Ausführung, erforderliche Proxmox-Befehle, die Proxmox-Versionsabfrage, die Verfügbarkeit eines Ubuntu-26.04-LXC-Templates und eine Namenskollision mit `ralf-standalone`.
- Geänderte Dateien: `scripts/ralf-standalone-bootstrap.sh`, `tests/bootstrap-preflight.sh`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: `bash -n` und ShellCheck ohne Befund; simulierte Tests für Erfolgsfall, fehlendes Template und bestehenden Containername erfolgreich; read-only Preflight auf dem realen Proxmox-Host erfolgreich; `git diff --check` ohne Befund.
- Nicht ausgeführte Prüfungen: Kein Test gegen eine reale Container-Erstellung oder Softwareinstallation, weil dieser Schritt ausschließlich den read-only Preflight implementiert und Live-Infrastruktur nicht verändert werden darf.
- Risiken oder Blocker: VMID, Storage, Netzwerk-Bridge und feste Ressourcenwerte sind für den Erzeugungsschritt noch nicht implementiert. Der Template-Abgleich setzt voraus, dass der Proxmox-Katalog einen Namen mit `ubuntu-26.04-standard` enthält.
- Nächster sinnvoller Zielbild-Eintrag: M-017 – sichere, explizit konfigurierte Erstellung des unprivilegierten LXC ergänzen.
- Veröffentlichung: Die Änderungen werden gemeinsam committed, gepusht und nach `main` gemergt.

## 2026-07-28 – Allgemeingültigen Codex-Auftrag veröffentlicht

- Bearbeitete Zielbild-IDs: P-002, A-014
- Ergebnis: `GOAL.md` wurde als allgemeingültiger und wiederverwendbarer Arbeitsauftrag für Codex CLI angelegt. `AGENTS.md`, `README.md` und `ZIELBILD.md` verweisen nun verbindlich auf diesen Auftrag. Der Goal-Auftrag verlangt ausdrücklich Ergebnisprotokoll, gezielten Commit und Push nach jedem Arbeitsdurchlauf.
- Geänderte Dateien: `GOAL.md`, `AGENTS.md`, `README.md`, `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Aktuelle Remote-Dateien wurden gelesen; Verweise, Prioritätsreihenfolge, Zielbild-IDs und sichtbarer Projektstatus wurden auf Konsistenz geprüft. Eine zwischenzeitliche README- und Ergebnis-Erweiterung zum Bootstrap-Preflight wurde beim erneuten Einlesen erhalten.
- Nicht ausgeführte Prüfungen: Keine Code-, Installations- oder Infrastrukturtests, da ausschließlich Projekt- und Agentendokumentation geändert wurde.
- Risiken oder Blocker: Die GitHub-Schreibvorgänge erzeugten mehrere aufeinanderfolgende Commits statt eines einzelnen atomaren Commits. Der Bootstrap ist weiterhin nur als ungefährlicher Preflight teilweise implementiert; Container-Erstellung und Softwareinstallation stehen aus.
- Nächster sinnvoller Zielbild-Eintrag: M-017 – sichere, explizit konfigurierte Erstellung des unprivilegierten LXC gemäß `GOAL.md` fortsetzen.
- Veröffentlichung: Alle Änderungen wurden durch GitHub-Schreibvorgänge direkt auf `main` committed und auf das Remote-Repository veröffentlicht; dieser Protokolleintrag bildet den abschließenden Commit des Arbeitsdurchlaufs.

## 2026-07-28 – Fehlende LXC-Ressourcenkonfiguration formalisiert

- Bearbeitete Zielbild-IDs: M-002, M-007, M-010, M-011, M-017, O-007, P-001
- Ergebnis: O-007 erfasst VMID, Ziel-Storage, Netzwerk-Bridge, CPU, RAM, Root-Disk-Größe und deren verbindliche Eingabeform als noch offene, vor der LXC-Erstellung notwendige Entscheidung. Es wurden keine Werte erfunden und keine Live-Ressourcen verändert.
- Geänderte Dateien: `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente und jüngste relevante Ergebnisse gelesen; Abhängigkeit zur sicheren LXC-Erstellung geprüft; Zielbild-ID und Tabellenstruktur kontrolliert; `git diff --check` wird vor dem Commit ausgeführt.
- Nicht ausgeführte Prüfungen: Keine Shell-, Installations- oder Infrastrukturtests, da ausschließlich ein Implementierungsblocker dokumentiert wurde und die bestehende Preflight-Implementierung unverändert blieb.
- Risiken oder Blocker: M-017 und D-001 bleiben bis zur Entscheidung O-007 blockiert.
- Nächster sinnvoller Zielbild-Eintrag: O-007
- Veröffentlichung: Die Dokumentationsänderungen werden gemeinsam committed, gepusht und nach `main` gemergt.

## 2026-07-31 – O-007 festgelegt und Ressourcenplan implementiert

- Bearbeitete Zielbild-IDs: O-007, M-021, M-022, O-008, P-001
- Ergebnis: O-007 ist abgeschlossen. Der sichere Plan-/Preflight-Pfad verwendet 4 Kerne, 12288 MiB RAM, 4096 MiB Swap und 40 GiB Root-Disk als feste Referenzwerte. VMID, Storage und Bridge werden eindeutig und nur lesend ermittelt; die sieben vorgesehenen CLI-Parameter überschreiben die Defaults beziehungsweise Auswahl. Mehrdeutige oder ungültige Werte brechen vor jeder Mutation ab. GPU-Passthrough wurde als separate offene Entscheidung O-008 dokumentiert und nicht implementiert.
- Geänderte Dateien: `scripts/ralf-standalone-bootstrap.sh`, `tests/bootstrap-preflight.sh`, `ZIELBILD.md`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: `bash -n`, ShellCheck soweit verfügbar, gültige Defaults, gültige CLI-Overrides, belegte VMID, mehrdeutige Storages, mehrdeutige Bridges, ungültiger Speicherwert, unbekannte Option, fehlender Parameter sowie `git diff --check`.
- Nicht ausgeführte Prüfungen: Keine echte LXC-Erstellung, kein Start/Stop und keine Softwareinstallation; der Planpfad bleibt absichtlich ohne Live-Mutation.
- Risiken oder Blocker: Die konkrete LXC-Erstellung und die Installation von Ubuntu-Aktualisierungen, Ollama, Modell und Open WebUI stehen weiterhin aus. O-008 bleibt für GPU-Unterstützung offen.
- Nächster sinnvoller Zielbild-Eintrag: M-017 – sichere LXC-Erstellung auf Basis des validierten Plans.
- Veröffentlichung: Die Änderungen werden gemeinsam committed, gepusht und nach `main` gemergt.

## 2026-07-31 – Sicheren Apply-Pfad für LXC-Erstellung implementiert

- Bearbeitete Zielbild-IDs: M-017, M-023, D-001, P-001
- Ergebnis: `--apply` wiederholt den vollständigen Preflight, vergleicht den unmittelbaren Plan und ruft anschließend genau einmal `pct create` mit unprivilegiertem LXC, DHCP, Referenzressourcen, Root-Disk und ohne Mountpoints oder GPU-Features auf. Die erzeugte Konfiguration und der gestoppte Status werden read-only geprüft. Bei Create- oder Prüfungsfehlern erfolgt kein automatisches Rollback; der Zustand wird eindeutig ausgegeben.
- Geänderte Dateien: `scripts/ralf-standalone-bootstrap.sh`, `tests/bootstrap-apply.sh`, `tests/bootstrap-preflight.sh`, `README.md`, `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: `bash -n`, ShellCheck, bestehende Preflight-Tests, Apply-Mocktests für Plan/Check ohne Create, exakte Overrides, belegte VMID, vorhandenen Namen, fehlendes Template, ungültigen Storage, ungültige Bridge, `pct create`-Fehler, erfolgreiche Create-Konfigurationsprüfung, unbekannte und widersprüchliche Optionen sowie `git diff --check`.
- Nicht ausgeführte Prüfungen: Kein realer `--apply`-Lauf und kein realer LXC wurden erstellt, gestartet, gestoppt oder gelöscht; dies war ausdrücklich ausgeschlossen.
- Risiken oder Blocker: D-001 bleibt `AKTIV`, bis ein realer LXC erfolgreich erstellt und geprüft wurde. Softwareinstallation und O-008 GPU-Entscheidung bleiben offen. Bei einem fehlgeschlagenen `pct create` wird kein automatisches Rollback versucht.
- Nächster sinnvoller Zielbild-Eintrag: Ein ausdrücklich beauftragter realer `--apply`-Validierungslauf für D-001.
- Veröffentlichung: Die Änderungen werden gemeinsam committed, gepusht und nach `main` gemergt.

## 2026-07-31 – D-001 real validiert

- Bearbeitete Zielbild-IDs: M-017, M-023, D-001, P-001
- Ergebnis: Der bestätigte Plan wurde genau einmal mit `sudo ./scripts/ralf-standalone-bootstrap.sh --apply` ausgeführt. VMID 100 wurde als unprivilegierter LXC `ralf-standalone` erstellt. Die anschließenden read-only Aufrufe `pct config 100` und `pct status 100` bestätigten die Zielkonfiguration und den Status `stopped`.
- Geänderte Dateien: `ZIELBILD.md`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Plan vor Apply; VMID-, Name-, Storage-, Bridge- und Template-Prüfung im Plan; genau ein realer Apply; read-only `pct config 100`; read-only `pct status 100`; Prüfung auf `unprivileged: 1`, 4 Kerne, 12288 MiB RAM, 4096 MiB Swap, 40-GiB-Root-Disk, DHCP über `vmbr0`, keine Mountpoints und keine GPU-Features.
- Nicht ausgeführte Prüfungen: Keine Softwareinstallation, kein Containerstart, kein Stop nach der Erstellung, kein Rollback, kein zweiter Apply-Versuch und keine weiteren Proxmox-Mutationen.
- Risiken oder Blocker: Der Container ist leer und gestoppt. Ubuntu-Paketupdates, Ollama, `qwen2.5-coder:7b`, Open WebUI und GPU-Unterstützung bleiben offen. O-008 bleibt als GPU-Entscheidung offen.
- Nächster sinnvoller Zielbild-Eintrag: Kontrolliertes Starten und Vorbereiten des leeren Ubuntu-LXC ohne RALF-Softwareinstallation.
- Veröffentlichung: Ausschließlich diese Dokumentationsänderungen werden committed, gepusht und nach `main` gemergt.

## 2026-07-31 – Erster LXC-Start und Basisvalidierung blockiert

- Bearbeitete Zielbild-IDs: M-024, M-017, M-023, P-001
- Ergebnis: Nach ausdrücklicher Freigabe wurde `pct start 100` genau einmal erfolgreich ausgeführt. VMID 100 läuft weiterhin als unprivilegierter `ralf-standalone`-LXC mit unveränderter Zielkonfiguration. Hostname, Ubuntu 26.04 LTS, Architektur `x86_64`, CPU, RAM, Swap, Root-Dateisystem und der erlaubte `/tmp`-Schreib-/Löschtest waren erfolgreich. `systemctl is-system-running` meldete `degraded`. `eth0` blieb auch nach einer begrenzten read-only Bereitschaftsprüfung `DOWN`; es gab keine IPv4-Adresse und keine Default-Route. Gateway-Erreichbarkeit, DNS-Auflösung und HTTPS-Erreichbarkeit der Ubuntu-Paketquelle schlugen deshalb fehl.
- Geänderte Dateien: `ZIELBILD.md`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Genau ein `pct start 100`; danach read-only `pct status 100`, `pct config 100`, Hostname, `/etc/os-release`, `uname -m`, `systemctl is-system-running`, IPv4-/Routen-/DNS-Prüfungen, begrenzte DHCP-Bereitschaftsprüfung, Gateway-Ping, DNS-Auflösung, HTTPS-Test, CPU-/Speicher-/Swap-/Root-Dateisystem-Prüfung, temporäre `/tmp`-Datei mit unmittelbarer Entfernung sowie Prüfung, dass die vorgesehenen RALF-Verzeichnisse noch nicht existieren.
- Nicht ausgeführte Prüfungen: Eine erfolgreiche Netzwerkvalidierung konnte wegen des fehlenden DHCP-Link-/Routenzustands nicht ausgeführt werden. Es wurden keine Updates, Paketinstallationen, RALF-Softwareinstallationen, Konfigurationsänderungen, Neustarts, Stopps, Rollbacks oder weiteren Proxmox-Mutationen durchgeführt.
- Risiken oder Blocker: Der Container läuft, ist aber ohne funktionsfähige Netzwerkanbindung. Der Blocker ist in einem separaten ausdrücklich freigegebenen Schritt zu diagnostizieren und zu beheben; bis dahin bleibt M-024 aktiv. Die temporäre Testdatei blieb nicht zurück. D-002 bis D-005 bleiben unverändert aktiv.
- Nächster sinnvoller Zielbild-Eintrag: M-024 – begrenzte Netzwerkdiagnose und anschließende read-only Basisvalidierung; danach erst Vorbereitung des Ubuntu-Systems.
- Veröffentlichung: Die Dokumentationsänderungen wurden in Commit `fbfbc5f` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-07-31 – M-024 Netzwerkdiagnose abgeschlossen, Reparatur ausstehend

- Bearbeitete Zielbild-IDs: M-024, P-001
- Ergebnis: VMID 100 läuft weiterhin unverändert. Die Proxmox-Konfiguration enthält `name=eth0`, `bridge=vmbr0`, `ip=dhcp` und `type=veth`, ohne `link_down`, VLAN-Tag oder Pending-Änderung. `vmbr0` ist `UP`/`LOWER_UP`; `veth100i0` existiert, ist administrativ `UP`, dem Bridge-Port zugeordnet, aber wegen des Gast-Links `NO-CARRIER`/`DOWN`. Im Gast existiert `/etc/systemd/network/eth0.network` mit passendem `Name = eth0` und `DHCP = ipv4`; Netplan-Dateien fehlen, NetworkManager ist nicht installiert. `systemd-networkd` ist aktiviert, schlägt aber zusammen mit `systemd-network-generator`, `systemd-resolved` und weiteren systemd-Diensten mit `status=243/CREDENTIALS` fehl. `networkctl` meldet `eth0` deshalb als `unmanaged`; es gibt keine IPv4-Adresse und keine Route. Die Ursache wird als `NETWORK_SERVICE` klassifiziert; der Host-veth-Zustand ist Folgeproblem, DHCP wurde wegen des nicht aktivierten Links nicht erreicht.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Status geprüft; `pct status 100`, `pct config 100`, `pct config 100 --current`, `pct pending 100`; Proxmox-Firewallabfragen; Host-Bridge-, veth-, Carrier- und VLAN-Prüfungen; Gast-Link, Adresse, Route, Operstate, Carrier, Netzwerkdienste, fehlgeschlagene Units, Konfigurationsdateilisten und -inhalte, `netplan get`, `networkctl` sowie begrenzte Journalabfragen. Es wurden keine Netzwerk-, Container- oder Betriebssystemänderungen ausgeführt.
- Nicht ausgeführte Prüfungen: Eine DHCP-, DNS- oder HTTPS-Erreichbarkeit war wegen des fehlenden Gast-Links nicht möglich. Die Journale enthalten keine persistenten Einträge; die genaue Kernel-Fehlermeldung zum Credential-Mount ist daher nicht verfügbar.
- Risiken oder Blocker: Die Ubuntu-26.04-Systemd-Version 259 benötigt für die im LXC scheiternde Credential-/Mount-Namespace-Einrichtung voraussichtlich die Proxmox-Containerfunktion `nesting`. Diese Funktion erweitert die für den Container sichtbaren procfs-/sysfs-Inhalte und muss vor Aktivierung ausdrücklich freigegeben werden. M-024 bleibt aktiv.
- Minimaler Reparaturvorschlag (nicht ausgeführt): Nach read-only Preflight `pct set 100 --features nesting=1` setzen und den Container einmal kontrolliert mit `pct restart 100` neu starten. Vor Anwendung sind `pct status 100`, `pct config 100`, `pct pending 100` sowie die unveränderte `net0`-Definition zu prüfen. Erwartet werden ein aktiver `systemd-networkd`, `eth0`/veth mit Carrier, DHCP-Adresse, Default-Route, DNS und HTTPS-Erreichbarkeit. Bei Fehlern keine Wiederholung; read-only Zustand erfassen. Rollback wäre `pct set 100 --delete features` und ein kontrollierter Neustart. Anschließend sind Proxmox- und Gast-Netzwerkprüfungen erneut auszuführen.
- Nächster sinnvoller Zielbild-Eintrag: M-024 – ausdrückliche Freigabe oder Ablehnung der `nesting=1`-Reparatur.
- Veröffentlichung: Dieser Eintrag wurde in Commit `993b378` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – M-024 Reparaturversuch fehlgeschlagen

- Bearbeitete Zielbild-IDs: M-024, P-001
- Ergebnis: Der bestätigte Preflight war erfolgreich: VMID 100 ist `ralf-standalone`, läuft und hatte vor der Mutation keine `features`-Konfiguration. `pct set 100 --features nesting=1` wurde genau einmal erfolgreich ausgeführt. Der ausdrücklich vorgegebene Befehl `pct restart 100` ist auf diesem Proxmox-Host nicht vorhanden und schlug mit `unknown command` fehl. Die read-only Prüfungen zeigten weiterhin `systemd-networkd`, `systemd-resolved`, `systemd-network-generator` und die zuvor betroffenen Basisdienste mit `243/CREDENTIALS`; `eth0` und `veth100i0` blieben ohne Carrier, DHCP-Adresse und Default-Route.
- Rollback: Der ausdrücklich vorgegebene Befehl `pct set 100 --delete features` wurde genau einmal mit Erfolg ausgeführt. Auch der darin vorgegebene `pct restart 100` schlug erneut als unbekannter Befehl fehl. Read-only ist die aktuelle Konfiguration ohne `features`, die Pending-Konfiguration enthält jedoch weiterhin `features: nesting=1`; VMID 100 läuft. Es wurde kein alternativer Neustart- oder Reparaturbefehl ausgeführt.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Status geprüft; Preflight von Status, Name und fehlender Features-Konfiguration; genau ein `pct set`; genau ein fehlgeschlagener `pct restart`; genau ein dokumentierter Rollback mit erneut fehlgeschlagenem `pct restart`; danach ausschließlich read-only `pct status`, `pct config`, `pct config --current`, `pct pending`, Rohkonfiguration, Proxmox-Bridge-/veth-/VLAN-Status, Gast-Link, Netzwerkdienste, fehlgeschlagene Units, DHCP-/Routen-, DNS- und HTTPS-Prüfungen.
- Nicht ausgeführte Prüfungen: Link, DHCP, Route, DNS und HTTPS konnten nach der Reparatur nicht erfolgreich validiert werden. Es wurden keine Paketinstallationen, Updates, weiteren Konfigurationsänderungen, alternativen Neustarts, Stopps, Rollbacks oder Reparaturversuche ausgeführt.
- Risiken oder Blocker: Der Container läuft ohne funktionierendes Netzwerk. Die Pending-Konfiguration enthält weiterhin `features: nesting=1`, obwohl die aktuelle Konfiguration dieses Feature nicht enthält. M-024 darf nicht abgeschlossen werden. Ein neuer, ausdrücklich freigegebener Schritt muss zuerst einen auf diesem Host unterstützten Lifecycle-Befehl und das Auflösen der Pending-Änderung festlegen.
- Nächster sinnvoller Zielbild-Eintrag: M-024 – unterstützten Proxmox-Lifecycle-Befehl und sicheren Umgang mit der verbleibenden Pending-Konfiguration entscheiden; danach read-only Netzwerkvalidierung wiederholen.
- Veröffentlichung: Dieser Eintrag wurde in Commit `928188b` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – Ausstehende features-Änderung bereinigt

- Bearbeitete Zielbild-IDs: M-024, P-001
- Ergebnis: Nach read-only Preflight von Status, aktueller Konfiguration und Pending-Konfiguration wurde `pct set 100 --revert features` genau einmal erfolgreich ausgeführt. Die anschließenden read-only Prüfungen bestätigen VMID 100 als `running`, eine aktuelle Konfiguration ohne `features` sowie keine ausstehende `features`-Änderung. Das Netzwerk wurde in diesem Bereinigungsschritt nicht verändert oder erneut konfiguriert.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: Vollständige Pflichtdokumente und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Status geprüft; read-only `pct status 100`, `pct config 100 --current 1`, `pct pending 100` vor der Mutation; genau ein `pct set 100 --revert features`; danach ausschließlich `pct config 100 --current 1`, `pct pending 100` und `pct status 100`; `git diff --check`.
- Nicht ausgeführte Prüfungen: Keine Netzwerk- oder Gastdienstprüfung, da dieser Auftrag ausschließlich die Pending-Bereinigung vorsah. Kein Reboot, Shutdown, Stop, Start, Paket- oder Softwarelauf und keine weitere Konfigurationsänderung.
- Risiken oder Blocker: M-024 bleibt unverändert `AKTIV`; das zuvor diagnostizierte Netzwerkproblem ist weiterhin offen und wurde nicht erneut validiert. `secrets/` blieb ungetrackt und unverändert.
- Nächster sinnvoller Zielbild-Eintrag: M-024 – separater, ausdrücklich freigegebener Reparaturschritt mit einem auf diesem Host unterstützten Proxmox-Lifecycle-Befehl.
- Veröffentlichung: Dieser Eintrag wurde in Commit `1a9481b` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – Proxmox-Lifecycle-Befehl read-only geprüft

- Bearbeitete Zielbild-IDs: M-024, P-001
- Ergebnis: Auf Proxmox VE `9.2.0` mit `pve-manager 9.2.4` ist `pct reboot` verfügbar. Die lokale Syntax lautet `pct reboot <vmid> [OPTIONS]`; `pct help reboot` dokumentiert die Option `--timeout <integer>` mit Wertebereich `0 - N` und ausdrücklich, dass der Container heruntergefahren, anschließend gestartet und dabei Pending-Änderungen angewendet werden. Ein Standardwert wird in `pct help reboot` nicht angegeben. Die lokale `lxc-stop`-Dokumentation beschreibt für den zugrunde liegenden Shutdown ohne expliziten Timeout 60 Sekunden bis zum erzwungenen Stop.
- Ergebnis VMID 100: `pct status 100` meldet `running`. `pct config 100 --current 1` enthält keine `features`. `pct pending 100` enthält keine ausstehende `features`-Änderung.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Status geprüft; `pveversion -v`, `pct help`, `pct help reboot`, `man pct`, lokale Proxmox-Implementierung, `lxc-stop --help`, `man lxc-stop`, `pct status 100`, `pct config 100 --current 1`, `pct pending 100` sowie `git diff --check`.
- Nicht ausgeführte Prüfungen: Kein `pct reboot`, `pct set`, `pct shutdown`, `pct stop`, `pct start`, keine Containeränderung und kein Netzwerk- oder Softwareeingriff.
- Risiken oder Blocker: M-024 bleibt `AKTIV`; der Lifecycle-Befehl ist nun bekannt, aber ein Reparaturversuch wurde nicht ausgeführt. `secrets/` blieb ungetrackt und unverändert.
- Nächster sinnvoller Zielbild-Eintrag: M-024 – separat freigegebener Reparaturversuch mit `pct reboot 100` und anschließender read-only Netzwerkvalidierung.
- Veröffentlichung: Dieser Eintrag wurde in Commit `378f7ca` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – M-024 Netzwerkreparatur erfolgreich validiert

- Bearbeitete Zielbild-IDs: M-024, A-016, P-001
- Ergebnis: Nach erfolgreichem read-only Preflight wurde `pct set 100 --features nesting=1` genau einmal ausgeführt. Die anschließende read-only Prüfung zeigte ausschließlich diese Pending-Änderung. `pct reboot 100 --timeout 120` wurde genau einmal erfolgreich ausgeführt und wendete die Änderung an. Danach war `nesting=1` wirksam und nicht mehr pending. `systemd-networkd`, `systemd-resolved`, `systemd-network-generator` sowie die zuvor mit `243/CREDENTIALS` fehlgeschlagenen Basisdienste liefen erfolgreich beziehungsweise als erfolgreiche oneshot-Dienste; `systemctl --failed` meldete keine Einheiten. `eth0` und `veth100i0` waren `UP`/`LOWER_UP`, DHCP vergab `10.10.200.11`, die Default-Route zeigte auf `10.10.0.1`, der Gateway-Ping war erfolgreich, DNS löste `archive.ubuntu.com` auf und HTTPS zur Ubuntu-Paketquelle war per `wget` erreichbar. Der Container bleibt laufend und enthält weiterhin keine RALF-Software.
- Geänderte Dateien: `ZIELBILD.md`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Status geprüft; read-only Preflight `pct status 100`, `pct config 100 --current 1`, `pct pending 100`; genau ein `pct set 100 --features nesting=1`; read-only Prüfung der ausschließlichen Pending-Änderung; genau ein `pct reboot 100 --timeout 120`; danach read-only Proxmox-Status, aktuelle Konfiguration und Pending-Zustand, Host-Bridge/veth/Carrier, Gast-Link, Netzwerkdienste und zuvor fehlgeschlagene Units, DHCP-Adresse, Default-Route, Gateway-Ping, DNS und HTTPS.
- Nicht ausgeführte Prüfungen: Keine Pakete, Updates, RALF-Verzeichnisse, Ollama-, Modell- oder Open-WebUI-Installation; kein zweiter Reboot-, Start- oder Reparaturversuch und kein Rollback.
- Risiken oder Blocker: Die DHCP-Adresse `10.10.200.11` ist dynamisch und nicht dauerhaft zugesichert. `nesting=1` erweitert die Container-Sicht auf procfs/sysfs und bleibt als notwendige Betriebsfunktion gesetzt. D-002 bis D-005 bleiben unverändert aktiv.
- Nächster sinnvoller Zielbild-Eintrag: M-013/M-017/M-020 – kontrollierte Vorbereitung des Ubuntu-Systems mit Updates und festgelegten Basisverzeichnissen, weiterhin ohne Ollama, Modell oder Open WebUI.
- Veröffentlichung: Dieser Eintrag wurde in Commit `d1221f5` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – `nesting=1` reproduzierbar im Bootstrap verankert

- Bearbeitete Zielbild-IDs: M-025, A-017, P-001
- Ergebnis: Der einzige `pct create`-Aufruf übergibt für die Ubuntu-26.04-Referenzinstallation explizit `--features nesting=1`. Plan und Check zeigen `LXC-Features: nesting=1`; die read-only Nachprüfung akzeptiert ausschließlich `features: nesting=1` und lehnt fehlende oder zusätzliche Features ab. VMID 100 wurde ausschließlich read-only geprüft und nicht verändert.
- Geänderte Dateien: `scripts/ralf-standalone-bootstrap.sh`, `tests/bootstrap-apply.sh`, `README.md`, `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente, jüngste Ergebnisse und Git-Status gelesen; `main`/`origin/main` und der Ausschluss von `secrets/` geprüft; read-only `pct status 100`, `pct config 100 --current 1`, `pct pending 100`; `bash -n`; ShellCheck; vollständige Preflight-Mocktests; Apply-Mocktests für Plan/Check ohne Create, exakte Ressourcen- und Feature-Übergabe, genau einen Create-Aufruf, belegte VMID, vorhandenen Namen, fehlendes Template, ungültigen Storage, ungültige Bridge, Create-Fehler, fehlende oder zusätzliche Features, unbekannte und widersprüchliche Optionen; `git diff --check`; Prüfung eindeutiger Zielbild-IDs und Status von M-025, A-017 sowie D-002 bis D-005.
- Nicht ausgeführte Prüfungen: Kein realer `--apply`- oder `pct create`-Lauf; kein `pct set`, `pct reboot`, `pct start`, `pct stop`, keine Paket- oder Softwareinstallation und keine Änderung an VMID 100.
- Risiken oder Blocker: `nesting=1` ist als Ubuntu-26.04-spezifische Betriebsanforderung der Referenzinstallation festgelegt und nicht als allgemeine Vorgabe späterer Betriebssysteme oder Plattformen. D-002 bis D-005 bleiben aktiv; Ollama, Modell und Open WebUI sind weiterhin nicht installiert.
- Nächster sinnvoller Zielbild-Eintrag: M-013/M-017/M-020 – kontrollierte Ubuntu-Vorbereitung mit Updates und festgelegten Basisverzeichnissen, weiterhin ohne Ollama, Modell oder Open WebUI.
- Veröffentlichung: Die Implementierungs- und Dokumentationsänderungen wurden in Commit `e6748a2` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – Ubuntu-Vorbereitung als Gastskript implementiert

- Bearbeitete Zielbild-IDs: M-026, A-018, P-001
- Ergebnis: `scripts/ralf-standalone-guest-prepare.sh` bietet einen vollständig read-only `--plan` sowie einen mutierenden `--apply` mit Preflight für root, Ubuntu 26.04, amd64/x86_64, systemd, `systemd-networkd`, IPv4, Default-Route, DNS, Ubuntu-Paketquelle und dpkg. Nach erfolgreichem Preflight werden nichtinteraktiv `apt-get update` und `apt-get full-upgrade` mit konservativer Konfigurationsbehandlung ausgeführt; anschließend werden ausschließlich die vier RALF-Basisverzeichnisse idempotent auf `root:root` und `0750` gesetzt. Der Abschluss prüft OS, dpkg, Paketmanagerzustand, Verzeichnismetadaten, Netzwerk und fehlgeschlagene Units und meldet `/var/run/reboot-required`, ohne neu zu starten. Ollama, Modell, Open WebUI, Docker, Podman, Datenbanken, GPU-Komponenten und weitere RALF-Software werden nicht installiert.
- Geänderte Dateien: `scripts/ralf-standalone-guest-prepare.sh`, `tests/guest-prepare.sh`, `README.md`, `ZIELBILD.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente, jüngste Ergebnisse, Git-Status und Secrets-Ausschluss gelesen; read-only `pct status 100`, `pct config 100 --current 1`, `pct pending 100`; Gast-`--plan`; `bash -n`; ShellCheck; Gast-Mocktests für Plan ohne Mutation, Nicht-root, falsches OS, falsche Ubuntu-Version, fehlendes Netzwerk, beschädigtes dpkg, erfolgreiche Paketbefehle, Fehler bei `apt-get update`, Fehler bei `full-upgrade`, exakte vier Verzeichnisse mit `root:root`/`0750`, wiederholte Ausführung, verbotene Installationsbefehle und reine Neustartmeldung; bestehende Bootstrap-Preflight- und Apply-Mocktests; `git diff --check`; Prüfung eindeutiger Zielbild-IDs.
- Nicht ausgeführte Prüfungen: Kein realer Gast-`--apply`, kein `apt-get update`, kein `apt-get full-upgrade`, kein `pct push` oder `pct exec`, kein Neustart und keine Paket-, Proxmox- oder Containeränderung. VMID 100 wurde nur read-only geprüft.
- Risiken oder Blocker: Die reale Gastvorbereitung und die spätere Weitergabe des Skripts in den LXC benötigen einen separaten, ausdrücklich bestätigten Ablauf. Ein fehlgeschlagener Paketbefehl kann einen teilweisen Paketstand hinterlassen; das Skript führt keinen Rollback und keinen Wiederholungsversuch aus. D-002 bis D-005 bleiben aktiv.
- Nächster sinnvoller Zielbild-Eintrag: M-013/M-017/M-020 – read-only Plan im laufenden VMID 100, danach separate Nutzerfreigabe für genau einen realen Vorbereitungslauf und anschließende read-only Validierung.
- Veröffentlichung: Skript, Tests und Dokumentation wurden in Commit `90296d5` gezielt committed und auf `origin/main` gepusht; `secrets/` blieb ungetrackt und unverändert.

## 2026-08-01 – Reale Ubuntu-Vorbereitung read-only geplant

- Bearbeitete Zielbild-IDs: M-026, A-018, P-001
- Ergebnis: Der reale Vorbereitungslauf in VMID 100 wurde ausschließlich geprüft und geplant. Das verwendete Skript `scripts/ralf-standalone-guest-prepare.sh` ist syntaktisch gültig und hat SHA-256 `1ed2cdb04e0cc45708339ee99ca7060d556d951a283184fa6b52c131d3b44480`. VMID 100 ist `running`, heißt `ralf-standalone`, läuft unprivilegiert mit `nesting=1`, besitzt keine erkannten Mountpoint- oder GPU-Einträge und hat keine Pending-Änderung. Im Gast wurden Ubuntu 26.04 LTS, `x86_64`, laufendes systemd und `systemd-networkd`, DHCP-Adresse `10.10.200.11`, Default-Route über `10.10.0.1`, DNS-Auflösung, HTTPS-Erreichbarkeit per `wget`, 37 GiB freien Root-Speicher, 12 GiB RAM, 4 GiB Swap und einen sauberen dpkg-Status bestätigt. Die konfigurierte Quelle steht in `/etc/apt/sources.list.d/ubuntu.sources` und verwendet `http://archive.ubuntu.com/ubuntu` für `resolute`, `resolute-updates` und `resolute-security`.
- Planlauf: Das versionierte Skript wurde mit `pct exec 100 -- bash -s -- --plan` ausschließlich über stdin ausgeführt. Es kündigte `apt-get update`, `apt-get full-upgrade`, genau die vier RALF-Verzeichnisse mit `root:root`/`0750`, keinen automatischen Neustart sowie den Ausschluss von Ollama, Modell, Open WebUI, Docker, Podman, Datenbanken und GPU-Komponenten an.
- Paketsimulation: `apt-get -s -o Dpkg::Options::=--force-confold full-upgrade` lief ohne Aktualisierung der Paketlisten erfolgreich und meldete `0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded`. Diese Vorschau ist wegen des bewusst nicht ausgeführten `apt-get update` ausdrücklich potenziell veraltet.
- Mutationsnachweis: Nach Plan und Simulation blieben Containerstatus, aktuelle Konfiguration und Pending-Zustand unverändert. Die vier RALF-Verzeichnisse und `/var/run/reboot-required` existieren weiterhin nicht; `dpkg --audit` bleibt sauber; es laufen keine `apt`-, `apt-get`-, `dpkg`- oder `unattended-upgrade`-Prozesse. Paketmanager-Lockdateien existieren, sind aber laut `fuser` nicht belegt.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: `AGENTS.md`, `GOAL.md`, `ZIELBILD.md` und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Ausschluss geprüft; `bash -n` und SHA-256 für das Gastskript; `pct status 100`, `pct config 100 --current 1`, `pct pending 100`; alle angeforderten Gastprüfungen für Hostname, OS, Architektur, systemd, Netzwerk, DNS, Speicher, dpkg, Paketquellen, Prozesse, Locks, Neustartmarker und Verzeichnisse; HTTPS-Test mit begrenztem `wget`; direkter Gast-Plan über stdin; read-only apt-Simulation; erneuter Mutationsnachweis; `git diff --check`.
- Nicht ausgeführte Prüfungen oder Änderungen: Kein `--apply`, kein `apt-get update`, kein echtes `apt-get full-upgrade`, keine Paketinstallation oder -entfernung, kein `mkdir`, `install -d`, `chmod`, `chown`, `pct push`, keine RALF-Softwareinstallation, kein Reboot, Stop oder Start. Die apt-Simulation ist keine Aktualisierung und kann veraltet sein.
- Risiken oder Blocker: Die vier Zielverzeichnisse fehlen erwartungsgemäß noch. Die Paketsimulation zeigt aktuell keine Änderungen, ersetzt aber keine frische Paketlistenaktualisierung. Ein späterer Apply kann einen teilweisen Paketstand oder einen Neustartbedarf hinterlassen; es gibt keinen automatischen Rollback oder zweiten Versuch.
- Nächster sinnvoller Zielbild-Eintrag: M-026/A-018 – ausdrückliche Nutzerfreigabe für genau einmal `pct exec 100 -- bash -s -- --apply < scripts/ralf-standalone-guest-prepare.sh`, danach ausschließlich read-only Validierung.
- Veröffentlichung: Dieser Planlauf wurde als Dokumentationsänderung in Commit `51a3b28` gezielt committed und auf `origin/main` gepusht; `ZIELBILD.md` blieb unverändert und `secrets/` ungetrackt.

## 2026-08-01 – Ubuntu-Vorbereitung in VMID 100 erfolgreich ausgeführt

- Bearbeitete Zielbild-IDs: M-026, A-018, P-001
- Ergebnis: Nach erneutem read-only Preflight und Bestätigung des unveränderten Skript-Hashes `1ed2cdb04e0cc45708339ee99ca7060d556d951a283184fa6b52c131d3b44480` wurde `pct exec 100 -- bash -s -- --apply < scripts/ralf-standalone-guest-prepare.sh` genau einmal ausgeführt. `apt-get update` und `apt-get full-upgrade` waren erfolgreich; 59 vorhandene Pakete wurden aktualisiert, 0 Pakete neu installiert und 0 Pakete entfernt. Die Paketaktualisierung meldete unter anderem einen automatischen Postfix-Dienstneustart durch den Pakettrigger, aber keinen Containerneustart.
- Abschlusszustand: `dpkg --audit` ist sauber. Es laufen keine apt-, apt-get-, dpkg- oder unattended-upgrade-Prozesse; die üblichen Lockdateien sind nicht belegt. `/etc/ralf/`, `/var/lib/ralf/ollama/`, `/var/lib/ralf/webui/` und `/var/log/ralf/` existieren jeweils als `root:root` mit Modus `0750`. Netzwerk und DNS funktionieren weiterhin (`10.10.200.11`, Default-Route `10.10.0.1`), HTTPS zur Ubuntu-Paketquelle ist erfolgreich, `systemctl --failed` meldet keine Units und `/var/run/reboot-required` existiert nicht. Ollama, Modell, Open WebUI, Docker, Podman und weitere RALF-Software wurden nicht installiert.
- Proxmox-Zustand: VMID 100 bleibt `running`; aktuelle Konfiguration und Pending-Zustand sind unverändert, weiterhin unprivilegiert mit `nesting=1`, DHCP über `vmbr0`, ohne Mountpoints oder GPU-Konfiguration.
- Geänderte Dateien: `Ergebnis.md`
- Ausgeführte Prüfungen: Pflichtdokumente und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Ausschluss geprüft; Skript-Syntax und SHA-256; read-only Preflight von VMID 100, Paketprozessen/-Locks, Netzwerk, DNS und HTTPS; genau ein bestätigter Apply-Lauf; danach ausschließlich read-only `pct status 100`, `pct config 100 --current 1`, `pct pending 100`, `dpkg --audit`, Paketprozesse/-Locks, Verzeichnisbesitzer/-modi, Netzwerk, DNS, HTTPS, `systemctl --failed`, `systemctl`-Zustand, `/var/run/reboot-required`, RALF-Software-Ausschluss und Root-Speicher.
- Nicht ausgeführte Prüfungen oder Änderungen: Kein zweiter Apply-Versuch, kein Rollback, kein `pct push`, kein `pct set`, kein Reboot, Stop oder Start und keine Ollama-, Modell-, Open-WebUI-, Docker-, Podman-, Datenbank- oder GPU-Installation.
- Risiken oder Blocker: Die vier Basisverzeichnisse sind vorbereitet, enthalten aber noch keine RALF-Anwendungssoftware. Der Root-Speicher liegt nach dem Upgrade bei rund 37 GiB frei; die DHCP-Adresse bleibt dynamisch. D-002 bis D-005 bleiben aktiv.
- Nächster sinnvoller Zielbild-Eintrag: M-014/M-015/M-016 – getrennte Planung und Freigabe der späteren Ollama-, Modell- und Open-WebUI-Installation.
- Veröffentlichung: Dieser erfolgreiche Lauf wurde als Dokumentationsänderung in Commit `02a573e` gezielt committed und auf `origin/main` gepusht; `ZIELBILD.md` blieb unverändert und `secrets/` ausgeschlossen.

## 2026-08-01 – Bootstrap als dauerhafte RALF-Basis festgelegt

- Bearbeitete Zielbild-IDs: M-003, M-006, M-014, M-015, M-016, M-017, M-020, M-027, M-028, O-002, O-003, O-004, O-009, A-007, A-008, A-009, A-019, A-020, A-021, P-001
- Ergebnis: Der Bootstrap ist nun verbindlich als dauerhaft betriebene, kleine modellfreie RALF-Basis dokumentiert. Er soll lokalen Zustand, installierte und erreichbare Komponenten, offene Setup-Schritte sowie Fehler und Warnungen anzeigen und später einen deterministischen Setup-Dialog, nachvollziehbare Installationspläne und ausdrücklich freigegebene Einzelschritte bereitstellen. Ein großes Administrationsinterface bleibt getrennt und optional. Ollama, `qwen2.5-coder:7b` und Open WebUI sind keine Bootstrap-Voraussetzungen mehr, sondern spätere auswählbare Komponenten beziehungsweise ein mögliches Referenzprofil. Die historische Festlegung bleibt über `ERSETZT`-Einträge und Nachfolger nachvollziehbar.
- Zielbildpflege: M-003, M-006 und M-017 sowie O-002 bis O-004 und A-007 bis A-009 wurden mit Nachfolgerverweisen ersetzt. M-014 bis M-016 wurden als `SPAETER` für optionale spätere Komponenten eingeordnet. M-027 und M-028 definieren den neuen aktiven Meilenstein; O-009 dokumentiert die offene Technikentscheidung für einen kleinen wartbaren Dienst und ein Webinterface. A-019 bis A-021 halten die dauerhafte Bootstrap-Richtung und den erreichten technischen Ausgangszustand fest. D-002 bis D-005 bleiben aktiv.
- Technischer Ausgangszustand: Der reale VMID-100-LXC bleibt als laufender unprivilegierter Ubuntu-26.04-Container mit `nesting=1`, funktionierendem Netzwerk, aktualisiertem Paketstand, vorbereiteten Basisverzeichnissen sowie reproduzierbaren Host- und Gastskripten erhalten.
- Geänderte Dateien: `ZIELBILD.md`, `README.md`, `Ergebnis.md`
- Ausgeführte Prüfungen: `AGENTS.md`, `GOAL.md`, `ZIELBILD.md` und jüngste Ergebnisse gelesen; Git-Synchronität und Secrets-Ausschluss geprüft; `git diff --check`; Prüfung eindeutiger Zielbild-IDs; Prüfung aller `ERSETZT`-Nachfolger auf vorhandene IDs; Suche nach weiterhin aktiven verpflichtenden Aussagen zu Ollama, `qwen2.5-coder:7b` oder Open WebUI; Prüfung, dass keine Skripte oder Tests geändert wurden.
- Nicht ausgeführte Prüfungen: Keine Code-, Shell-, Installations- oder Infrastrukturprüfungen, da dieser Arbeitsdurchlauf ausschließlich Dokumentation und Zielbild ändert.
- Risiken oder Blocker: Die minimale Technik für Bootstrap-Dienst und Webinterface ist mit O-009 weiterhin offen. Der modellfreie Statusdienst und sein kleines Webinterface sind noch nicht implementiert; es wurden keine Framework- oder Programmiersprachenentscheidungen vorweggenommen.
- Nächster sinnvoller Zielbild-Eintrag: O-009 – Entscheidung über die möglichst kleine technische Umsetzung des dauerhaften Bootstrap- und Statusdienstes.
- Veröffentlichung: Dieser Dokumentationslauf wird gezielt committed und auf `origin/main` gepusht; Code, VMID 100 und `secrets/` bleiben unverändert beziehungsweise ausgeschlossen.
