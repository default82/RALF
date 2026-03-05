# Issue Drafts - Phase 4 Betriebsreife

Dieses Dokument enthaelt direkt nutzbare Issue-Entwuerfe fuer Phase 4.

## 1) Semaphore-first Betrieb als Standard festlegen

**Titel**

`Betriebsreife: Semaphore-first Betrieb als Standard festlegen`

**Body**

```md
## Kontext
Nach Foundation- und Erweiterungs-Validierung soll der wiederholbare Regelbetrieb auf `Semaphore-first` umgestellt werden.

## Ziel
Den operativen Standard so festlegen, dass geplante Aenderungen primaer ueber Semaphore laufen und manuelle Shell-Ausfuehrung nur als dokumentierte Ausnahme erfolgt.

## Preconditions
- [ ] Foundation Core + Foundation Services validiert
- [ ] Erweiterungs-Smokes abgeschlossen
- [ ] Mindestens ein belastbarer Template-Run in Semaphore vorhanden

## Vorschlag
- Betriebsregel `Semaphore-first` verbindlich dokumentieren
- Standard-Runbooks auf Semaphore-Pipelines referenzieren
- Ausnahmeprozess fuer manuelle Ausfuehrungen definieren (mit Nachweis)

## Risikoanalyse
- **Warnung:** Teilteams nutzen weiterhin ad-hoc Shell-Commands ohne Nachweis
- **Warnung:** Unvollstaendige Template-Abdeckung fuer Sonderfaelle
- **Blocker:** Kritische Betriebsaufgaben sind ueber Semaphore nicht ausfuehrbar

## Akzeptanzkriterien
- [ ] Betriebsstandard `Semaphore-first` ist dokumentiert und freigegeben
- [ ] Kernablaeufe sind als Semaphore-Templates verfuegbar
- [ ] Ausnahmeprozess ist beschrieben und testweise angewendet
- [ ] Nachweis/Gate-Status dokumentiert
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Verlinkte Dokumentaenderung mit Betriebsstandard
- Liste der relevanten Templates inkl. Zweck
- Beispiel-Ausnahme mit Begruendung und Rueckfuehrung

## Gate-Status
`Warnung` (initial) -> auf `OK` bei dokumentiertem Standard und nutzbarer Template-Abdeckung
```

## 2) Regelmaessige Drift-/Health-Checks etablieren

**Titel**

`Betriebsreife: regelmaessige Drift-/Health-Checks etablieren`

**Body**

```md
## Kontext
Stabiler Betrieb benoetigt wiederkehrende technische Pruefungen auf Drift, Dienstzustand und Erreichbarkeit.

## Ziel
Einen periodischen, reproduzierbaren Check-Prozess etablieren, der Drift und Health-Abweichungen frueh erkennt und nachvollziehbar dokumentiert.

## Vorschlag
- Zeitplan fuer Drift-/Health-Checks festlegen (z. B. taeglich/woechentlich)
- Check-Ausfuehrung ueber Semaphore oder standardisierte Skripte kapseln
- Ergebnisartefakte zentral sammeln und mit Gate-Status versehen

## Risikoanalyse
- **Warnung:** Checks laufen, aber Ergebnisse werden nicht ausgewertet
- **Warnung:** Zu viele false positives verringern Verlaesslichkeit
- **Blocker:** Kritische Drift bleibt trotz Checks unentdeckt

## Akzeptanzkriterien
- [ ] Check-Frequenz und Verantwortlichkeit sind definiert
- [ ] Automatisierter Check-Run ist technisch funktionsfaehig
- [ ] Ergebnisse werden zentral abgelegt (inkl. Zeitstempel)
- [ ] Eskalationspfad bei `Warnung`/`Blocker` ist dokumentiert
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Zeitplan/Runbook fuer wiederkehrende Checks
- Beispielhafte Check-Ergebnisse
- Dokumentierter Eskalationspfad

## Gate-Status
`Warnung` (initial) -> auf `OK` bei laufendem Rhythmus und belastbarer Auswertung
```

## 3) Jede Aenderung mit Gate-Status und Nachweis abschliessen

**Titel**

`Betriebsreife: jede Aenderung mit Gate-Status und Nachweis abschliessen`

**Body**

```md
## Kontext
RALF verlangt Nachvollziehbarkeit vor Autonomie. Jede relevante Aenderung soll mit explizitem Gate-Status und belastbarem Nachweis abgeschlossen werden.

## Ziel
Einen verbindlichen Abschlussstandard durchsetzen, der fuer jede Aenderung Gate-Status, Nachweis und ggf. Folgeaktion einheitlich dokumentiert.

## Vorschlag
- Einheitliches Abschlussschema definieren (Template/Checklist)
- Pflichtfelder in PRs/Issues konsequent anwenden
- Review-Prozess auf Vollstaendigkeit von Nachweis + Gate ausrichten

## Risikoanalyse
- **Warnung:** Formale Angabe ohne ausreichende Evidenz
- **Warnung:** Uneinheitliche Qualitaet der Nachweise je Teammitglied
- **Blocker:** Kritische Aenderungen ohne Gate-Entscheidung im Betrieb

## Akzeptanzkriterien
- [ ] Verbindliches Abschlussschema ist dokumentiert
- [ ] PR/Issue-Prozess erzwingt Gate-Status + Nachweis
- [ ] Stichprobe bestaetigt konsistente Anwendung
- [ ] Offene Abweichungen sind mit Massnahmen versehen
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Verlinktes Abschlussschema (Template/Checklist)
- Beispielhafte PRs/Issues mit vollstaendigem Gate-Nachweis
- Stichprobenprotokoll mit Ergebnis

## Gate-Status
`Warnung` (initial) -> auf `OK` bei konsistenter und nachweisbarer Anwendung
```