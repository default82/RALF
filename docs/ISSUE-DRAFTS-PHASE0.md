# Issue Drafts - Phase 0 Governance

Dieses Dokument enthaelt direkt nutzbare Issue-Entwuerfe fuer Phase 0.

## 1) Kanonischen Stand bestaetigen

**Titel**

`Governance: kanonischen Dokumentstand fuer MVP bestaetigen`

**Body**

```md
## Kontext
Vor operativer Umsetzung der technischen Phasen muss der kanonische Governance-Stand explizit bestaetigt werden.

Betroffene Dokumente:
- `docs/CHARTA.md` (v1.2)
- `docs/ZIELBILD.md` (v1.3)
- `docs/BETRIEBSVERFASSUNG.md` (v1.2)

## Ziel
Formale Bestaetigung der gueltigen Versionen und Geltung als operativer Referenzstand fuer das MVP.

## Vorschlag
- Versionen und Inhalte im Release-Snapshot gegenpruefen
- Dokumentierten Entscheidungsnachweis zur Bestaetigung erfassen
- Ergebnis als Gate-Entscheidung festhalten

## Risikoanalyse
- **Warnung:** Uneinheitlicher Dokumentstand fuehrt zu widerspruechlichen Entscheidungen
- **Blocker:** Keine explizite Bestaetigung des Governance-Standes vor technischer Umsetzung

## Akzeptanzkriterien
- [ ] Versionen in Charta/Zielbild/Betriebsverfassung sind eindeutig dokumentiert
- [ ] Bestaetigung durch Owner ist nachvollziehbar festgehalten
- [ ] Release-Snapshot ist konsistent zum bestaetigten Stand
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Verlinkter Entscheidungsnachweis (Issue/PR/Protokoll)
- Aktualisierter oder bestaetigter Snapshot in `README.md`

## Gate-Status
`Warnung` (initial) -> auf `OK` bei formaler Bestaetigung und konsistentem Snapshot
```

## 2) Entscheidungsweg und Gate-Regeln operativ festschreiben

**Titel**

`Governance: Entscheidungsweg und Gate-Regeln als operativen Standard festschreiben`

**Body**

```md
## Kontext
RALF verlangt fuer jede relevante Aenderung den verbindlichen Operativablauf und eindeutiges Gatekeeping (`OK|Warnung|Blocker`).

## Ziel
Den operativen Standard so festschreiben, dass der 8-Schritt-Entscheidungsweg inklusive Nachweis/Gate bei allen relevanten Aenderungen reproduzierbar angewendet wird, inklusive DNS-Standard `internal-zone` fuer `*.${RALF_DOMAIN}`.

## Vorschlag
- Einheitliches Schema fuer Vorschlag, Risiko, Alternativen, Entscheidung, Nachweis und Gate definieren
- PR-/Issue-Prozess auf diese Pflichtfelder ausrichten
- Kurz-Runbook fuer Teamanwendung dokumentieren
- Interne DNS-Zone als verbindliche Betriebsregel referenzieren

## Risikoanalyse
- **Warnung:** Prozess wird formal genannt, aber nicht konsistent angewendet
- **Blocker:** Aenderungen ohne Gate-Status und belastbaren Nachweis

## Akzeptanzkriterien
- [ ] Operatives Schema ist dokumentiert und teamweit referenzierbar
- [ ] PR-/Issue-Templates bilden den Ablauf ab
- [ ] DNS-Standard `internal-zone` ist als Pflichtvorgabe dokumentiert
- [ ] Stichprobe bestaetigt praktische Anwendung
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Verlinktes Runbook/Schema
- Beispielhafte PR/Issue mit vollstaendigem Ablauf und Gate
- Kurzes Stichprobenprotokoll
- DNS-Manifest-Artefakte (`$RUNTIME_DIR/dns/records.hosts`, `$RUNTIME_DIR/dns/zone.bind`)
- OPNsense/Unbound-Artefakte (`$RUNTIME_DIR/dns/unbound-host-overrides.csv`, `$RUNTIME_DIR/dns/unbound-custom-options.conf`)
- Resolver-Verifikation (`$RUNTIME_DIR/dns/dns-verify.jsonl`)

## Gate-Status
`Warnung` (initial) -> auf `OK` bei dokumentierter und nachweisbarer Anwendung
```