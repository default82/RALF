# RALF MVP - Operativer Master-Plan

Stand: 2026-03-05

## 1. Zweck

Dieses Dokument konsolidiert die operative Planung aus den kanonischen Grundlagen und den vorhandenen Issue-Drafts.
Ziel ist eine direkt ausfuehrbare Reihenfolge mit klaren Gates, Nachweisen und Blocker-Regeln.

## 2. Verbindliche Quellen

- `docs/CHARTA.md`
- `docs/ZIELBILD.md`
- `docs/BETRIEBSVERFASSUNG.md`
- `docs/IP-KONVENTION.md`
- `docs/ISSUE-PRIORITAETEN-PHASE1-4.md`
- `docs/ISSUE-DRAFTS-PHASE1.md`
- `docs/ISSUE-DRAFTS-PHASE2.md`
- `docs/ISSUE-DRAFTS-PHASE3.md`
- `docs/ISSUE-DRAFTS-PHASE4.md`

## 3. Priorisierte Reihenfolge (MVP)

Die Reihenfolge folgt den bestehenden Issue-Prioritaeten 1-15.

1. Foundation: MinIO bereitstellen und State-/Artefaktpfad verifizieren
2. Foundation: PostgreSQL bereitstellen und Basiszugriff pruefen
3. Foundation: Gitea bereitstellen und als kanonisches Remote etablieren
4. Foundation: Semaphore bereitstellen und Initial-Templates seeden
5. Foundation Core End-to-End validieren
6. Foundation Services: Vaultwarden bereitstellen
7. Foundation Services: Prometheus bereitstellen
8. Foundation Services: Foundation-Smokes vollstaendig durchfuehren
9. Erweiterung: n8n bereitstellen
10. Erweiterung: KI-Instanz bereitstellen
11. Erweiterung: Matrix bereitstellen
12. Erweiterung: Erweiterungs-Smokes vollstaendig durchfuehren
13. Betriebsreife: Semaphore-first Betrieb als Standard festlegen
14. Betriebsreife: regelmaessige Drift-/Health-Checks etablieren
15. Betriebsreife: jede Aenderung mit Gate-Status und Nachweis abschliessen

## 4. Ausfuehrungsprotokoll pro Arbeitspaket

Jedes Issue wird nach dem verbindlichen Operativablauf abgearbeitet:

1. Vorschlag
2. Begruendung
3. Risikoanalyse
4. Alternativen
5. Entscheidung
6. Ausfuehrung
7. Dokumentation
8. Gate-Status (`OK|Warnung|Blocker`)

## 5. Standard-Kommandopfad

Lokale Vorpruefung:

```bash
bash -n bootstrap/start.sh bootstrap/bootrunner.sh bootstrap/validate.sh
bash bootstrap/validate.sh --dry-run --runtime-dir /tmp/ralf-runtime
```

Planlauf:

```bash
bash bootstrap/start.sh
```

Kontrollierter Apply-Lauf:

```bash
bash bootstrap/start.sh --apply
```

Nicht-interaktiv (Automation):

```bash
bash bootstrap/start.sh --apply --yes --non-interactive --config bootstrap/bootstrap.env
```

Service-Smoke:

```bash
bash bootstrap/validate.sh --config bootstrap/bootstrap.env
```

## 6. Pflichtartefakte je Schritt

- Entscheidungsnachweis (Issue/PR-Text)
- Ergebnisnachweis (Logs, Smoke-Ausgabe, ggf. Screenshots)
- Gate-Status (`OK|Warnung|Blocker`)
- Runtime-Artefakte unter `RUNTIME_DIR`:
  - `logs/run-<id>.log`
  - `checkpoints.jsonl`
  - `summary.md`
  - `smoke-results.jsonl`

## 7. Gate-Regeln fuer Fortschritt

- `OK`: naechster Schritt freigegeben
- `Warnung`: nur mit bewusster Owner-Bestaetigung fortfahren
- `Blocker`: kein Fortschritt, erst Stabilisierung und Ursachenanalyse

## 8. Risiko-Register (aktuell)

1. Fehlende oder ungueltige Proxmox API-Credentials im Apply-Modus
2. Port-/Netzkonflikte im Segment `10.10.0.0/16`
3. Persistenzfehler bei Volume-Mounts
4. Integrationsfehler trotz erfolgreicher Einzel-Smokes
5. Drift zwischen Dokumentation (`TODO`) und technischer Ausfuehrungslogik (`bootrunner`)

## 9. Planungsentscheidung (aufgeloest)

Owner-Entscheidung: `Matrix` gehoert zum MVP-Backlog, damit eine Kommunikationsbasis mit RALF bereitsteht.

Konsequenz:

- Phase 3 enthaelt verbindlich `n8n`, `KI` und `Matrix`.
- Die Prioritaetenliste wurde auf 15 Issues erweitert.

## 10. Naechste operative Planungsschritte

1. Matrix-Issue in GitHub anlegen (auf Basis `docs/ISSUE-DRAFTS-PHASE3.md`).
2. Erweiterungs-Smoke-Issue-Abhaengigkeiten auf `n8n + KI + Matrix` setzen.
3. Bei Umsetzungsstart die Reihenfolge 9 -> 10 -> 11 -> 12 strikt einhalten.