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
