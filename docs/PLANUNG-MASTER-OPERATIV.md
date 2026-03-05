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

Die Reihenfolge folgt den bestehenden Issue-Prioritaeten 1-14.

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
11. Erweiterung: Erweiterungs-Smokes vollstaendig durchfuehren
12. Betriebsreife: Semaphore-first Betrieb als Standard festlegen
13. Betriebsreife: regelmaessige Drift-/Health-Checks etablieren
14. Betriebsreife: jede Aenderung mit Gate-Status und Nachweis abschliessen

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

## 9. Aktueller Planungs-Blocker (Rückfragepflicht)

Es gibt eine nicht vollstaendig aufloesbare Abweichung aus den `*.md`-Quellen:

- `TODO.md` und die priorisierte 1-14 Liste enthalten in Phase 3 nur `n8n` und `KI`.
- `bootstrap/lib/phase_catalog.sh` und `bootstrap/hooks/085-matrix.sh` enthalten zusaetzlich `Matrix` in Phase 3.

Damit ist unklar, ob `Matrix` Teil des MVP-Backlogs sein soll oder bewusst ausserhalb bleibt.

## 10. Naechste Aktion nach Rueckmeldung

Nach Owner-Entscheidung zu `Matrix` wird die Prioritaetenliste entweder:

- unveraendert fortgefuehrt (Matrix explizit out-of-scope), oder
- auf 15 Issues erweitert (zusaetzliches Matrix-Issue in Phase 3).