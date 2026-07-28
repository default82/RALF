# Goal: RALF anhand des Zielbilds weiterentwickeln

Dieser Auftrag ist der allgemeingültige Startauftrag für Codex CLI und andere Coding-Agenten im Repository RALF. Er wird für neue Arbeitsdurchläufe wiederverwendet. Konkrete Ziele, Entscheidungen, Grenzen und Status stehen in `ZIELBILD.md`.

## Verbindliche Vorbereitung

1. Lies `AGENTS.md` vollständig.
2. Lies `GOAL.md` vollständig.
3. Lies `ZIELBILD.md` vollständig.
4. Lies `README.md`.
5. Lies die jüngsten relevanten Einträge in `Ergebnis.md`.
6. Prüfe den aktuellen Git-Status, den aktiven Branch und die vorhandenen Dateien.
7. Behandle `ZIELBILD.md` als verbindliche Quelle für Ziele, Entscheidungen, Grenzen, Status und Definition of Done.

## Auswahl der nächsten Aufgabe

Wähle genau den nächsten sinnvoll umsetzbaren Arbeitsschritt nach diesen Regeln:

1. Bearbeite zuerst den aktuellen Meilenstein.
2. Berücksichtige vorrangig Einträge mit dem Status `AKTIV`.
3. Beachte Abhängigkeiten und die Definition of Done.
4. Bearbeite nur einen zusammenhängenden, überprüfbaren Arbeitsschritt gleichzeitig.
5. Setze keine mit `SPAETER`, `IDEE`, `VERWORFEN` oder `ERSETZT` markierten Punkte um.
6. Triff keine Produkt-, Architektur- oder Plattformentscheidung, die in `ZIELBILD.md` noch als `OFFEN` gekennzeichnet ist.
7. Implementiere keine zukünftige Abstraktion vorsorglich, wenn sie für den aktuellen Meilenstein nicht benötigt wird.

Wenn eine offene Entscheidung die Umsetzung blockiert, erfinde keine Entscheidung. Beende den Arbeitsdurchlauf mit:

- blockierender Zielbild-ID,
- benötigter Entscheidung,
- unmittelbar betroffener Aufgabe,
- höchstens drei sachlich unterschiedlichen Optionen,
- einer begründeten Empfehlung.

## Planung vor Änderungen

Nenne vor der Implementierung knapp:

- die bearbeiteten Zielbild-IDs,
- das konkrete Ergebnis dieses Arbeitsschritts,
- die voraussichtlich betroffenen Dateien,
- die vorgesehenen Prüfungen,
- erkennbare Risiken oder Blocker.

Halte den Umfang klein. Ändere keine Dateien, die für den gewählten Arbeitsschritt nicht benötigt werden.

## Umsetzung

- Bevorzuge einfache, lesbare und reproduzierbare Lösungen.
- Baue nur, was der aktuelle Meilenstein verlangt.
- Vermeide unnötige Frameworks, Abstraktionen und Abhängigkeiten.
- Hinterlege keine Zugangsdaten, Tokens, Passwörter oder andere Geheimnisse im Repository.
- Verändere keine bestehende Live-Infrastruktur ohne ausdrücklichen Auftrag.
- Erstelle, lösche oder verändere keine realen Proxmox-Container, VMs, Storages oder Netzwerke, solange dies nicht ausdrücklich verlangt wird.
- Überschreibe keine vorhandenen Ressourcen stillschweigend.
- Installations- und Deploymentcode muss verständliche Fehler liefern.
- Befehle und Skripte müssen möglichst wiederholbar und sicher abbrechbar sein.
- Verwende sichere Standardeinstellungen.
- Ergänze Kommentare nur dort, wo das Verhalten nicht aus dem Code verständlich wird.

## Validierung

Führe nach der Umsetzung die relevanten Prüfungen aus. Dazu können gehören:

- Syntaxprüfung,
- Linting,
- Unit- oder Integrationstests,
- ShellCheck,
- Testlauf mit ungefährlichen Eingaben,
- Prüfung erzeugter Konfigurationen,
- Prüfung von Fehler- und Abbruchpfaden,
- Vergleich mit der Definition of Done.

Behaupte keine erfolgreiche Prüfung, die nicht tatsächlich ausgeführt wurde. Nicht ausführbare Prüfungen müssen mit dem konkreten Grund genannt werden.

## Pflege von ZIELBILD.md

Aktualisiere `ZIELBILD.md` im selben Arbeitsdurchlauf, wenn sich ein Ziel, eine Anweisung, eine Entscheidung, ein Status, ein Prüfkriterium oder eine Grenze verändert.

- Bestehende Einträge nicht löschen.
- Stabile IDs nicht verändern oder wiederverwenden.
- Erledigte Punkte auf `ABGESCHLOSSEN` setzen.
- Abgelöste Punkte auf `ERSETZT` setzen und den Nachfolger nennen.
- Bewusst aufgegebene Punkte auf `VERWORFEN` setzen.
- Neue verbindliche Vorgaben mit neuer stabiler ID ergänzen.
- Keine ausführlichen Überlegungen oder Gesprächsprotokolle eintragen.
- Ergebnisse und Entscheidungen knapp und eindeutig formulieren.
- Das Datum `Stand` aktualisieren, wenn die Datei verändert wurde.

## Pflege der übrigen Dokumentation

Aktualisiere `README.md`, wenn sich Installation, Bedienung, unterstützter Funktionsumfang, Voraussetzungen, bekannte Einschränkungen oder Projektstruktur ändern.

Ändere `AGENTS.md` nur, wenn sich dauerhaft geltende Arbeitsregeln für alle zukünftigen Coding-Agenten ändern.

Ändere `GOAL.md` nur, wenn sich der allgemeingültige Arbeitsauftrag ändert.

Ändere `LICENSE` nicht ohne ausdrückliche Anweisung.

## Ergebnisprotokoll, Commit und Push

1. Ergänze `Ergebnis.md` nach jedem Arbeitsdurchlauf append-only um einen neuen datierten Eintrag.
2. Nenne mindestens bearbeitete Zielbild-IDs, Ergebnis oder Fehler, geänderte Dateien, ausgeführte Prüfungen, nicht ausgeführte Prüfungen mit Begründung, Risiken oder Blocker und den nächsten sinnvollen Zielbild-Eintrag.
3. Prüfe vor dem Commit den Diff und den Ausschluss von Geheimnissen.
4. Committe ausschließlich die zum Arbeitsdurchlauf gehörenden Dateien mit einer knappen, aussagekräftigen Commit-Nachricht.
5. Pushe den Commit auf den vorgesehenen Remote-Branch.
6. Behaupte weder Commit noch Push als erfolgreich, wenn der Vorgang nicht tatsächlich erfolgreich war.

## Abschluss des Arbeitsdurchlaufs

Beende den Durchlauf nach einem abgeschlossenen, überprüfbaren Arbeitsschritt. Arbeite nicht automatisch den gesamten zukünftigen Meilenstein ab.

Berichte abschließend:

1. bearbeitete Zielbild-IDs,
2. umgesetztes Ergebnis,
3. geänderte Dateien,
4. ausgeführte Prüfungen und deren Resultate,
5. nicht ausgeführte Prüfungen mit Begründung,
6. offene Risiken oder Blocker,
7. nächster sinnvoller Zielbild-Eintrag,
8. Branch, Commit und Push-Status.

Ein Arbeitsschritt gilt nur als abgeschlossen, wenn Implementierung, Validierung, notwendige Dokumentationspflege, Ergebnisprotokoll, Commit und Push zusammen erledigt wurden.