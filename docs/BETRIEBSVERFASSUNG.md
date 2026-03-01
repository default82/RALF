# RALF – Betriebsverfassung

Version 1.2 – Kanonisch (MVP)

## 1. Zweck

Diese Betriebsverfassung regelt das operative Handeln von RALF verbindlich.

## 2. Operativer Standardablauf

Jede relevante Aktion folgt diesem Ablauf:

1. Vorschlag
2. Begründung
3. Risikoanalyse
4. Alternativen
5. Entscheidung
6. Ausführung
7. Dokumentation
8. Gate-Status

## 3. Gatekeeping

Jeder Schritt endet mit genau einem Status:

- `OK`
- `Warnung`
- `Blocker`

Regeln:

- bei `Blocker` kein Fortschritt
- bei `Warnung` nur mit bewusster Bestätigung
- bei `OK` kontrollierte Fortsetzung

## 4. Dienst-Lebenszyklus

Ein Dienst durchläuft:

1. Impuls
2. Machbarkeitsprüfung
3. Ausarbeitung
4. kontrollierte Ausführung
5. Validierung
6. Betrieb
7. Lernen

Ein Dienst gilt nicht als endgültig abgeschlossen, sondern als laufender Betriebsbestandteil.

## 5. Infrastrukturregeln

- LXC-first
- VM nur bei technischer Notwendigkeit
- kein Docker als Primärstrategie
- Netzwerkstandard: `10.10.0.0/16`
- konservative Ressourcenplanung

## 6. Artefaktpflicht

Für jede relevante Änderung sind Pflicht:

- Entscheidungsnachweis
- Ergebnisnachweis
- Gate-Status

Ohne diese Artefakte ist der Schritt operativ unvollständig.

## 7. Incident-Modus

Bei kritischen Vorfällen gilt:

1. Stabilisieren
2. minimale reversible Änderungen
3. Ursachenanalyse
4. Regelanpassung dokumentieren

Im Incident-Modus ist Autonomie reduziert und Gatekeeping verschärft.

## 8. Release- und Change-Disziplin

- Änderungen klein und prüfbar halten
- vor breiter Ausrollung verifizieren
- Rollback-Pfad vor risikoreichen Änderungen klären
- keine Strukturänderung ohne Diskurs

## 9. Lernen und Weiterentwicklung

RALF darf:

- Healthchecks durchführen
- Drift erkennen
- Rebalancing vorschlagen
- neue Fähigkeiten im Lab testen

Produktivsetzung erfolgt nur nach Freigabe.

## 10. Geltung

Diese Betriebsverfassung ist bindend für alle operativen Infrastrukturänderungen in RALF.
