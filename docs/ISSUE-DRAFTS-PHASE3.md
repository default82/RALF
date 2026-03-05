# Issue Drafts - Phase 3 Erweiterung

Dieses Dokument enthaelt direkt nutzbare Issue-Entwuerfe fuer Phase 3.

## 1) n8n bereitstellen

**Titel**

`Erweiterung: n8n bereitstellen`

**Body**

```md
## Kontext
n8n gehoert zur Phase 3 (Erweiterung) und wird erst nach erfolgreichem Abschluss der Foundation-Validierungen ausgerollt.

## Ziel
n8n in der vorgesehenen LXC-Umgebung bereitstellen und den Basisbetrieb verifizieren (Erreichbarkeit, Login, einfacher Workflow-Test).

## Preconditions
- [ ] Foundation Core End-to-End Gate = `OK`
- [ ] Foundation Services Smokes abgeschlossen
- [ ] Netz-/IP-Plan in `bootstrap/bootstrap.env` ist aktuell

## Vorschlag
- Hook `bootstrap/hooks/070-n8n.sh` im Plan- und Apply-Modus ausfuehren
- n8n-Container auf Ziel-IP/Port starten
- Basiszugriff und Erstlogin verifizieren
- Minimalen Test-Workflow erstellen und einmal ausfuehren

## Risikoanalyse
- **Warnung:** Fehlkonfiguration bei Persistenz/Volume, Workflows gehen bei Restart verloren
- **Warnung:** Offener Endpunkt ohne angemessene Absicherung
- **Blocker:** Kein stabiler Start oder kein reproduzierbarer Workflow-Run

## Akzeptanzkriterien
- [ ] n8n-LXC laeuft stabil (`running`)
- [ ] Endpoint/UI ist erreichbar
- [ ] Login funktioniert
- [ ] Test-Workflow laeuft erfolgreich
- [ ] Ergebnis/Nachweis dokumentiert
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus + Endpoint-Erreichbarkeit
- Test-Workflow-Run mit Ergebnis

## Gate-Status
`Warnung` (initial) -> auf `OK` bei stabilem Betrieb und erfolgreichem Test-Workflow
```

## 2) KI-Instanz bereitstellen

**Titel**

`Erweiterung: KI-Instanz bereitstellen`

**Body**

```md
## Kontext
Die KI-Instanz gehoert zur Phase 3 (Erweiterung) und folgt nach erfolgreicher Foundation- und Basis-Erweiterungsvalidierung.

## Ziel
Eine KI-Instanz in der vorgesehenen LXC-Umgebung bereitstellen und den technischen Basisbetrieb verifizieren (Erreichbarkeit, Health, einfacher Inferenz-Test).

## Preconditions
- [ ] Foundation Core End-to-End Gate = `OK`
- [ ] Foundation Services Smokes abgeschlossen
- [ ] n8n-Bereitstellung ist abgeschlossen oder bewusst als parallel markiert

## Vorschlag
- Hook `bootstrap/hooks/080-ki.sh` im Plan- und Apply-Modus ausfuehren
- KI-Container auf Ziel-IP/Port starten
- Health-/Ready-Endpunkt pruefen
- Minimalen Inferenz- oder API-Test durchfuehren

## Risikoanalyse
- **Warnung:** Ressourcenengpaesse (RAM/CPU) auf dem Host
- **Warnung:** Modell-/Runtime-Konfiguration nicht reproduzierbar
- **Blocker:** Service nicht erreichbar oder kein erfolgreicher Inferenz-Test

## Akzeptanzkriterien
- [ ] KI-LXC laeuft stabil (`running`)
- [ ] Endpoint/API ist erreichbar
- [ ] Health/Ready pruefbar
- [ ] Einfacher API-/Inferenz-Test erfolgreich
- [ ] Ergebnis/Nachweis dokumentiert
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus + Endpoint-Erreichbarkeit
- Erfolgreicher Basis-API-/Inferenz-Test

## Gate-Status
`Warnung` (initial) -> auf `OK` bei stabilem Betrieb und erfolgreichem Basis-Test
```

## 3) Erweiterungs-Smokes durchfuehren

**Titel**

`Erweiterung: Erweiterungs-Smokes vollstaendig durchfuehren`

**Body**

```md
## Kontext
Nach Bereitstellung der Phase-3-Dienste (n8n, KI-Instanz) ist ein gesamthafter Smoke-Lauf erforderlich.

## Ziel
Alle Erweiterungs-Smokes reproduzierbar ausfuehren, Ergebnisse zentral dokumentieren und den finalen Gate-Status fuer Phase 3 setzen.

## Abhaengige Issues
- [ ] #<n8n-Issue-ID>
- [ ] #<KI-Issue-ID>

## Vorschlag
- Vollstaendigen Smoke-Lauf fuer Erweiterungsdienste ausfuehren
- Ergebnisse in Runtime-Artefakten dokumentieren
- Warnungen/Blocker klassifizieren und konkrete Folgeaktion benennen

## Risikoanalyse
- **Warnung:** Teilweise erfolgreiche Smokes ohne stabile Integrationskette
- **Warnung:** Flaky Checks durch Startreihenfolge oder Timing
- **Blocker:** Wiederholte Fehlschlaege in kritischen Erweiterungsdiensten

## Akzeptanzkriterien
- [ ] Erweiterungs-Smoke-Lauf vollstaendig ausgefuehrt
- [ ] n8n und KI technisch verifiziert
- [ ] Ergebnisse sind reproduzierbar und dokumentiert
- [ ] Rest-Risiken sind transparent klassifiziert
- [ ] Gate-Status gesetzt (`OK|Warnung|Blocker`)

## Nachweis
- Ausfuehrungslog der Erweiterungs-Smokes
- Ergebnisartefakte (z. B. Runtime-Log/JSONL)
- Gate-Entscheidungsnotiz mit Begruendung

## Gate-Status
`Warnung` (initial) -> auf `OK` nur bei reproduzierbar erfolgreichem Gesamt-Smoke
```