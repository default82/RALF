# AGENTS.md

Diese Datei enthält verbindliche Arbeitsanweisungen für Codex CLI und andere Coding-Agenten im Repository RALF.

## Vor jeder Änderung

1. Lies diese Datei vollständig.
2. Lies `ZIELBILD.md` vollständig.
3. Prüfe den aktuellen Repository-Stand und vorhandene Änderungen.
4. Arbeite nur am tatsächlich beauftragten Schritt.
5. Vermeide Architekturentscheidungen, die für den aktuellen Schritt nicht notwendig sind.

## Quellen der Wahrheit

Bei Widersprüchen gilt diese Reihenfolge:

1. die aktuelle ausdrückliche Nutzeranweisung,
2. `ZIELBILD.md`,
3. `AGENTS.md`,
4. `README.md`,
5. bestehender Code und Kommentare.

Widersprüche dürfen nicht stillschweigend aufgelöst werden. Dokumentiere die gewählte Auflösung knapp in `ZIELBILD.md`, wenn sie Ziele oder Entscheidungen verändert.

## Pflege von ZIELBILD.md

`ZIELBILD.md` ist bei jeder Änderung mitzupflegen, die mindestens einen der folgenden Punkte betrifft:

- Projektziele,
- aktive oder abgeschlossene Anweisungen,
- technische oder organisatorische Entscheidungen,
- Grenzen und Nicht-Ziele,
- Meilensteine oder deren Status,
- unterstützte beziehungsweise zurückgestellte Plattformen,
- Definition of Done.

Regeln für die Pflege:

- Keine langen Gedankengänge, Gesprächsprotokolle oder Alternativdiskussionen aufnehmen.
- Jede Anweisung knapp, eindeutig und für einen späteren Agenten verständlich formulieren.
- Abgeschlossene oder verworfene Einträge nicht löschen.
- Stattdessen den Status ändern und bei Bedarf einen kurzen Ergebnissatz ergänzen.
- Neue Entscheidungen erhalten eine stabile Kennung.
- Offene Ideen klar von beschlossenen Vorgaben trennen.

## Aktueller Arbeitsmodus

RALF wird zunächst durch Vibe Coding und kleine, überprüfbare Schritte aufgebaut.

Für den aktuellen ersten Meilenstein gilt:

- Zielplattform ist Proxmox VE.
- Es entsteht genau ein unprivilegierter LXC-Container.
- Modelllaufzeit, Modell und kleine Weboberfläche dürfen zunächst gemeinsam in diesem Container liegen.
- Daten und Konfiguration dürfen zunächst lokal im Container gespeichert werden.
- SQLite darf eingebettet verwendet werden, falls eine Komponente es benötigt.
- Der Software-Stack darf zunächst fest gewählt werden.
- Noch keine automatische Hardwareerkennung, Größenberechnung oder dynamische Modellauswahl bauen.
- Noch keine endgültige Definition von `ralf-core` erzwingen.
- Noch keine allgemeine Datenbank-, MCP-, Adapter- oder Multi-Plattform-Architektur implementieren, solange sie nicht für den aktiven Meilenstein erforderlich ist.

## Entwicklungsgrundsätze

- Praktische Funktion vor vorzeitiger Generalisierung.
- Kleine, nachvollziehbare Änderungen vor großen Umbauten.
- Reproduzierbarkeit vor manuellen Einmal-Schritten.
- Sichere Standardwerte vor stillen Annahmen.
- Keine unnötigen Abhängigkeiten.
- Keine Produktbindung in langfristigen Schnittstellen, solange eine konkrete Bindung nicht ausdrücklich Teil des aktuellen Referenz-Deployments ist.
- Docker darf langfristig unterstützt werden, ist aber nicht die Grundlage des ersten Proxmox-Deployments.
- Vorhandene Infrastruktur soll langfristig nutzbar bleiben; RALF soll keine doppelten Dienste erzwingen.

## Sicherheit und Änderungen am Host

- Keine destruktiven Host-Aktionen ohne ausdrückliche Anweisung.
- Keine bestehenden Container, VMs, Storage-Inhalte, Netzwerke oder Konfigurationen überschreiben.
- Zugangsdaten und Tokens nie in das Repository committen.
- Beispielkonfigurationen verwenden Platzhalter.
- Installationsschritte sollen bei Fehlern verständlich abbrechen.
- Ein erneuter Lauf soll möglichst sicher sein und keinen unbekannten Zustand erzeugen.

## Qualität

Jede Implementierungsänderung soll, soweit für den aktuellen Stand sinnvoll, enthalten:

- eine klare Ausführungsmöglichkeit,
- verständliche Fehlermeldungen,
- einen einfachen Health- oder Funktionstest,
- aktualisierte Dokumentation,
- keine unaufgeforderten Nebenfunktionen.

Vor Abschluss einer Aufgabe:

1. Änderungen und Diff prüfen.
2. Relevante Tests oder Syntaxprüfungen ausführen.
3. `README.md` nur aktualisieren, wenn sich die öffentliche Nutzung oder der sichtbare Projektstand ändert.
4. `ZIELBILD.md` aktualisieren, wenn sich Ziel, Anweisung, Entscheidung oder Status geändert hat.
5. Offen gebliebene Punkte klar benennen.

## Aktuelle Definition of Done

Der erste Standalone-Meilenstein ist abgeschlossen, wenn ein reproduzierbarer Installationsweg auf Proxmox einen unprivilegierten LXC mit Modell, Modelllaufzeit und kleiner Weboberfläche erzeugt und anschließend nachweist, dass:

- die Weboberfläche erreichbar ist,
- das Modell eine Testanfrage beantwortet,
- notwendige Daten einen Neustart überleben,
- der Container nach einem Neustart selbstständig wieder funktionsfähig wird,
- die Installation aus einem definierten Ausgangszustand erneut erstellt werden kann.
