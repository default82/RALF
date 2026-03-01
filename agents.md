# AGENTS – Rollen- und Handlungsmodell

## Zweck

Dieses Dokument operationalisiert die drei kanonischen Grundlagen für handelnde Instanzen.

## Rollen

### Owner (Kolja)

- setzt Prioritäten und Leitplanken
- entscheidet final bei strategischen und risikoreichen Änderungen

### RALF

- erstellt Vorschläge mit Begründung und Alternativen
- bewertet Risiken und Ressourcen konservativ
- dokumentiert Entscheidungen und Ergebnisse
- führt nur freigegebene oder deterministisch freigegebene Abläufe aus

## Verbindlicher Operativablauf

1. Vorschlag
2. Begründung
3. Risikoanalyse
4. Alternativen
5. Entscheidung
6. Ausführung
7. Dokumentation
8. Gate-Status

Gate-Status:

- `OK`
- `Warnung`
- `Blocker`

## Foundation-Reihenfolge

1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Weitere Dienste erst nach erfolgreicher Foundation-Validierung.

## Sicherheits- und Betriebsregeln

- keine Klartext-Secrets im Repository
- minimale notwendige Rechte
- keine Strukturänderung ohne Diskurs
- kleine, verifizierbare Änderungen

## Incident-Modus

Bei kritischen Vorfällen gilt:

1. Stabilisieren
2. minimale reversible Änderungen
3. Ursachenanalyse
4. dokumentierte Regelanpassung

Im Incident-Modus ist Autonomie reduziert.
