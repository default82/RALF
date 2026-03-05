# Issue Drafts - Phase 2 Foundation Services

Dieses Dokument enthaelt direkt nutzbare Issue-Entwuerfe fuer Phase 2.

## 1) Vaultwarden bereitstellen

**Titel**

`Foundation Services: Vaultwarden bereitstellen`

**Body**

```md
## Kontext
Vaultwarden gehoert zu den Foundation-Services (Phase 2) und darf erst nach erfolgreicher Foundation-Core-Validierung ausgerollt werden.

Foundation-Core (Gate vorher erforderlich):
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore
+ End-to-End-Validierung abgeschlossen

## Ziel
Vaultwarden in der vorgesehenen LXC-Umgebung bereitstellen und den sicheren Basisbetrieb verifizieren (Erreichbarkeit, Persistenz, Admin-Zugang, Service-Health).

## Preconditions
- [ ] Foundation Core End-to-End hat finalen Gate-Status `OK`
- [ ] Netz-/IP-Plan in `bootstrap/bootstrap.env` ist aktuell
- [ ] Keine Klartext-Secrets im Repository (Secrets nur ueber Laufzeit/Umgebungswerte)

## Vorschlag
- Hook `bootstrap/hooks/050-vaultwarden.sh` im Plan- und Apply-Modus ausfuehren
- Vaultwarden-Container auf Ziel-IP/Port starten
- Persistenzpfad pruefen (Daten bleiben nach Neustart erhalten)
- Basis-Health und Login-Endpunkte verifizieren

## Begruendung
- Passwort-/Secret-Management ist ein zentraler Betriebsdienst
- Fruehe Bereitstellung reduziert manuelle Secret-Streuung
- Entspricht der vorgesehenen Phase-2-Reihenfolge

## Risikoanalyse
- **Warnung:** Exponierte Endpunkte ohne ausreichende Absicherung (TLS/Netzsegment)
- **Warnung:** Persistenz/Volume falsch gebunden, Datenverlustrisiko bei Restart
- **Blocker:** Kein stabiler Dienststart oder kein reproduzierbarer Zugriff

## Alternativen
- Externer Passwortdienst statt lokaler Vaultwarden-Instanz
- Spaetere Bereitstellung nach Prometheus (nicht ideal fuer fruehe Secret-Disziplin)

## Akzeptanzkriterien
- [ ] Vaultwarden-LXC laeuft stabil (`running`)
- [ ] Dienst ist auf geplantem Endpoint erreichbar
- [ ] Persistenztest nach Restart erfolgreich
- [ ] Admin-/Initialzugriff funktioniert technisch
- [ ] Sicherheitsbasis dokumentiert (Netzgrenzen, Exposition, Secret-Handling)
- [ ] Ergebnis/Nachweis im Runtime- oder Betriebsprotokoll dokumentiert
- [ ] Gate-Status fuer dieses Issue gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Konfiguration in `bootstrap/bootstrap.env` pruefen
- [ ] Hook `050-vaultwarden.sh` im Plan-Modus pruefen
- [ ] Hook `050-vaultwarden.sh` im Apply-Modus ausfuehren
- [ ] Endpoint- und Persistenz-Smoke durchfuehren
- [ ] Sicherheitsnotiz + Nachweis + Gate-Status dokumentieren

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus + Endpoint-Erreichbarkeit
- Persistenztest (vor/nach Restart)
- Kurze Sicherheitsdokumentation (ohne Secrets im Klartext)

## Gate-Status
`Warnung` (initial) -> auf `OK` nur bei stabilem Betrieb, erfolgreicher Persistenz und dokumentierter Sicherheitsbasis
```

## 2) Prometheus bereitstellen

**Titel**

`Foundation Services: Prometheus bereitstellen`

**Body**

```md
## Kontext
Prometheus gehoert zu den Foundation-Services (Phase 2) und wird nach erfolgreicher Foundation-Core-Validierung ausgerollt.

Foundation-Core (Gate vorher erforderlich):
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore
+ End-to-End-Validierung abgeschlossen

## Ziel
Prometheus in der vorgesehenen LXC-Umgebung bereitstellen und die Basisbeobachtung verifizieren (Erreichbarkeit, Targets, Metrikabruf, Persistenz).

## Preconditions
- [ ] Foundation Core End-to-End hat finalen Gate-Status `OK`
- [ ] Netz-/IP-Plan in `bootstrap/bootstrap.env` ist aktuell
- [ ] Ziel-Services fuer erste Scrapes sind definiert (mind. Prometheus self-target)

## Vorschlag
- Hook `bootstrap/hooks/060-prometheus.sh` im Plan- und Apply-Modus ausfuehren
- Prometheus-Container auf Ziel-IP/Port starten
- Basis-Scrape-Config validieren (mind. `up` fuer self-target)
- Erste Runtime- und Service-Metriken abrufen und dokumentieren

## Begruendung
- Monitoring frueh in Phase 2 reduziert Blindflug bei folgenden Deployments
- Reproduzierbare Health-Sicht unterstuetzt Gate-Entscheidungen
- Entspricht der vorgesehenen Reihenfolge der Foundation-Services

## Risikoanalyse
- **Warnung:** Falsch konfigurierte Targets liefern Scheinerfolg (UI erreichbar, aber keine verwertbaren Daten)
- **Warnung:** Port-/Netzkonflikte im Segment `10.10.0.0/16`
- **Blocker:** Kein stabiler Metrikabruf oder Prometheus startet nicht reproduzierbar

## Alternativen
- Externes Monitoring statt lokaler Prometheus-Instanz
- Monitoring erst in spaeterer Phase (nicht empfohlen, geringere Betriebstransparenz)

## Akzeptanzkriterien
- [ ] Prometheus-LXC laeuft stabil (`running`)
- [ ] Web-UI ist auf geplantem Endpoint erreichbar
- [ ] Mindestens ein Target ist `UP` (inkl. self-target)
- [ ] Abfrage einer Basis-Metrik funktioniert (z. B. `up`, `process_cpu_seconds_total`)
- [ ] Persistenzverhalten ist dokumentiert (Daten nach Restart plausibel vorhanden)
- [ ] Ergebnis/Nachweis im Runtime- oder Betriebsprotokoll dokumentiert
- [ ] Gate-Status fuer dieses Issue gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Konfiguration in `bootstrap/bootstrap.env` pruefen
- [ ] Hook `060-prometheus.sh` im Plan-Modus pruefen
- [ ] Hook `060-prometheus.sh` im Apply-Modus ausfuehren
- [ ] Targets/Scrapes validieren und Basis-Queries testen
- [ ] Nachweis + Gate-Status dokumentieren

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus + Endpoint-Erreichbarkeit
- Screenshot/Log der Target-Health (`UP`)
- Erfolgreiche Beispiel-Query(s)

## Gate-Status
`Warnung` (initial) -> auf `OK` nur bei stabilem Betrieb und reproduzierbarem Metrikabruf
```

## 3) Foundation-Smokes vollstaendig durchfuehren

**Titel**

`Foundation Services: Foundation-Smokes vollstaendig durchfuehren`

**Body**

```md
## Kontext
Nach Bereitstellung der Foundation-Services (Vaultwarden, Prometheus) ist ein vollstaendiger Smoke-Lauf erforderlich, um die Betriebsfaehigkeit der Foundation als Ganzes nachzuweisen.

## Ziel
Alle vorgesehenen Foundation-Smokes reproduzierbar ausfuehren, Ergebnisse zentral dokumentieren und einen finalen Gate-Status fuer Phase 2 ableiten.

## Scope
- Service-Smokes fuer Foundation-Core und Foundation-Services
- Endpunkt-, Port-, Dienst- und Basisfunktionspruefung
- Zusammenfuehrung der Ergebnisse in einem verwertbaren Nachweis

## Abhaengige Issues
- [ ] #<Vaultwarden-Issue-ID>
- [ ] #<Prometheus-Issue-ID>
- [ ] #<Foundation-Core-E2E-Issue-ID>

## Vorschlag
- Vollstaendigen Smoke-Lauf mit `bootstrap/validate.sh` ausfuehren
- Ergebnisse auswerten und in `smoke-results.jsonl` konsolidieren
- Offene Warnungen/Blocker klassifizieren und dokumentieren
- Finalen Gate-Status fuer Foundation Services setzen

## Begruendung
- Einzelne erfolgreiche Deployments ersetzen keine Gesamtvalidierung
- Einheitlicher Smoke-Nachweis verbessert Freigabequalitaet
- Schafft klare Ausgangslage fuer Phase 3 (Erweiterung)

## Risikoanalyse
- **Warnung:** Teilweise gruen, aber inkonsistente Integrationspfade
- **Warnung:** Flaky Checks (zeitabhaengig/nicht reproduzierbar)
- **Blocker:** Wiederholte Smoke-Fehlschlaege bei kritischen Diensten

## Akzeptanzkriterien
- [ ] `bootstrap/validate.sh --config bootstrap/bootstrap.env` laeuft vollstaendig
- [ ] Alle Foundation-relevanten Services sind im Ergebnis enthalten
- [ ] Kritische Checks (Dienst aktiv, Port offen, Basisfunktion) sind erfolgreich
- [ ] `smoke-results.jsonl` ist vorhanden und auswertbar
- [ ] Warnungen/Blocker sind mit Ursache und naechster Aktion dokumentiert
- [ ] Gate-Status fuer dieses Issue ist gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Preconditions und Konfiguration pruefen
- [ ] Foundation-Smoke-Lauf starten
- [ ] Ergebnisse sammeln und konsolidieren
- [ ] Abweichungen klassifizieren (Warnung/Blocker)
- [ ] Nachweis + Gate-Status dokumentieren

## Nachweis
- Ausfuehrungslog von `bootstrap/validate.sh`
- `smoke-results.jsonl`
- Kurzbewertung je Dienst (Status + ggf. Ursache)
- Finale Gate-Entscheidungsnotiz

## Gate-Status
`Warnung` (initial) -> auf `OK` nur bei reproduzierbar erfolgreichem Gesamt-Smoke ohne offene kritische Blocker
```