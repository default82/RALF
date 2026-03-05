# Issue Drafts - Phase 1 Foundation Core

Dieses Dokument enthaelt direkt nutzbare Issue-Entwuerfe fuer Phase 1.

## 1) MinIO bereitstellen und State-/Artefaktpfad verifizieren

**Titel**

`Foundation: MinIO bereitstellen und State-/Artefaktpfad verifizieren`

**Body**

```md
## Kontext
MinIO ist Schritt 1 der verbindlichen Foundation-Reihenfolge:
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Ohne verifizierten Object-Storage fehlen belastbare Artefakt-/State-Pfade fuer nachfolgende Foundation-Schritte.

## Ziel
MinIO in der vorgesehenen LXC-Umgebung bereitstellen und den vorgesehenen State-/Artefaktpfad technisch verifizieren (Erreichbarkeit, Schreib-/Lesezugriff, Persistenz).

## Vorschlag
- Hook `bootstrap/hooks/010-minio.sh` im Plan- und Apply-Modus ausfuehren
- MinIO-Container auf Ziel-IP/Port starten
- Bucket/Pfad fuer RALF-Artefakte anlegen (gemaess `bootstrap/bootstrap.env`)
- Technischen Smoke fuer MinIO-Zugriff dokumentieren

## Begruendung
- Entspricht der kanonischen Reihenfolge und reduziert Folgefehler in Phase 1
- Schafft einen klaren Nachweis fuer Artefaktpersistenz
- Ermoeglicht reproduzierbare Foundation-Validierung

## Risikoanalyse
- **Warnung:** Port-/Netzkonflikte im Zielsegment `10.10.0.0/16`
- **Warnung:** Fehlkonfiguration bei Volumes/Persistenz
- **Blocker:** MinIO nicht erreichbar oder kein stabiler Schreib-/Lesezugriff

## Alternativen
- MinIO als externen Dienst nutzen (schneller Start, aber weniger Kontrolle im LXC-first Modell)
- Lokale Dateiablage statt Object Storage (nicht empfohlen, schlechtere Skalierung/Nachvollziehbarkeit)

## Akzeptanzkriterien
- [ ] MinIO-LXC laeuft stabil (`running`)
- [ ] Dienst ist aktiv und auf geplantem Port erreichbar
- [ ] Bucket/Pfad fuer RALF-Artefakte existiert
- [ ] Testobjekt kann geschrieben, gelesen und wieder geloescht werden
- [ ] Ergebnis/Nachweis im Runtime- oder Betriebsprotokoll dokumentiert
- [ ] Gate-Status fuer dieses Issue gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Konfiguration in `bootstrap/bootstrap.env` pruefen
- [ ] Hook `010-minio.sh` im Plan-Modus pruefen
- [ ] Hook `010-minio.sh` im Apply-Modus ausfuehren
- [ ] Smoke-Test auf MinIO-Zugriff durchfuehren
- [ ] Nachweis + Gate-Status dokumentieren

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus
- Objektzugriffstest (Put/Get/Delete)

## Gate-Status
`Warnung` (initial) -> bei erfolgreicher Verifizierung auf `OK` setzen
```

## 2) PostgreSQL bereitstellen und Basiszugriff pruefen

**Titel**

`Foundation: PostgreSQL bereitstellen und Basiszugriff pruefen`

**Body**

```md
## Kontext
PostgreSQL ist Schritt 2 der verbindlichen Foundation-Reihenfolge:
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Nach verifiziertem MinIO ist eine stabile Datenbank-Basis fuer nachgelagerte Services erforderlich.

## Ziel
PostgreSQL in der vorgesehenen LXC-Umgebung bereitstellen und den Basiszugriff technisch verifizieren (Erreichbarkeit, Authentifizierung, einfache Query).

## Vorschlag
- Hook `bootstrap/hooks/020-postgresql.sh` im Plan- und Apply-Modus ausfuehren
- PostgreSQL-Container auf Ziel-IP/Port starten
- Basis-DB und technischen Test-User gemaess `bootstrap/bootstrap.env` pruefen/anlegen
- Verbindungs- und Query-Smoke dokumentieren

## Begruendung
- Entspricht der kanonischen Foundation-Reihenfolge
- Schafft belastbare Grundlage fuer Gitea/Semaphore-nahe Datenabhaengigkeiten
- Reduziert Integrationsrisiken in den Folgeschritten

## Risikoanalyse
- **Warnung:** Portkonflikt oder Netzrouting-Fehler im Segment `10.10.0.0/16`
- **Warnung:** Auth-/HBA-Fehlkonfiguration verhindert Remote-Zugriff
- **Blocker:** DB startet nicht stabil oder Query-Test scheitert reproduzierbar

## Alternativen
- Externe PostgreSQL-Instanz verwenden (schneller, aber weniger LXC-first Konformitaet)
- SQLite/Dateibasiert fuer Teilservices (nicht als Foundation-Standard geeignet)

## Akzeptanzkriterien
- [ ] PostgreSQL-LXC laeuft stabil (`running`)
- [ ] Dienst ist aktiv und auf geplantem Port erreichbar
- [ ] Authentifizierter Login mit technischem User funktioniert
- [ ] Einfache Query (`SELECT 1;`) liefert erfolgreiches Ergebnis
- [ ] Ergebnis/Nachweis im Runtime- oder Betriebsprotokoll dokumentiert
- [ ] Gate-Status fuer dieses Issue gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Konfiguration in `bootstrap/bootstrap.env` pruefen
- [ ] Hook `020-postgresql.sh` im Plan-Modus pruefen
- [ ] Hook `020-postgresql.sh` im Apply-Modus ausfuehren
- [ ] DB-Verbindungs- und Query-Smoke durchfuehren
- [ ] Nachweis + Gate-Status dokumentieren

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus
- Erfolgreicher Login + Query-Test (`SELECT 1;`)

## Gate-Status
`Warnung` (initial) -> bei erfolgreicher Verifizierung auf `OK` setzen
```

## 3) Gitea bereitstellen und als kanonisches Remote etablieren

**Titel**

`Foundation: Gitea bereitstellen und als kanonisches Remote etablieren`

**Body**

```md
## Kontext
Gitea ist Schritt 3 der verbindlichen Foundation-Reihenfolge:
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Nach MinIO und PostgreSQL wird ein stabiles, internes Git-Remote als kanonische Quelle fuer RALF benoetigt.

## Ziel
Gitea in der vorgesehenen LXC-Umgebung bereitstellen und als kanonisches Remote fuer das RALF-Repository verifizieren.

## Vorschlag
- Hook `bootstrap/hooks/030-gitea.sh` im Plan- und Apply-Modus ausfuehren
- Gitea-Container auf Ziel-IP/Port starten
- Admin-Initialisierung und Basis-Org/Repo pruefen
- RALF-Repo als Remote anbinden und Push/Pull-Test durchfuehren

## Begruendung
- Entspricht der kanonischen Foundation-Reihenfolge
- Schafft nachvollziehbare, interne Source-of-Truth fuer Code und Automatisierung
- Reduziert Abhaengigkeit von externen Remotes im Betriebsmodell

## Risikoanalyse
- **Warnung:** Port-/Reverse-Proxy-Konflikte im Netzsegment `10.10.0.0/16`
- **Warnung:** SSH/HTTP-Remote-Konfiguration inkonsistent
- **Blocker:** Kein stabiler Push/Pull auf das kanonische Gitea-Remote

## Alternativen
- Externes Git-Hosting als primaeres Remote (schneller, aber nicht LXC-first/kanonisch)
- Mirror-only Betrieb ohne kanonisches internes Remote (nicht empfohlen)

## Akzeptanzkriterien
- [ ] Gitea-LXC laeuft stabil (`running`)
- [ ] Web-UI ist auf geplantem Endpoint erreichbar
- [ ] Technischer Zugriff (Admin + Repo-Rechte) funktioniert
- [ ] RALF-Repo ist in Gitea angelegt oder korrekt verbunden
- [ ] Push und Pull gegen Gitea-Remote funktionieren erfolgreich
- [ ] Ergebnis/Nachweis im Runtime- oder Betriebsprotokoll dokumentiert
- [ ] Gate-Status fuer dieses Issue gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Konfiguration in `bootstrap/bootstrap.env` pruefen
- [ ] Hook `030-gitea.sh` im Plan-Modus pruefen
- [ ] Hook `030-gitea.sh` im Apply-Modus ausfuehren
- [ ] Repo/Remote-Einrichtung (HTTP oder SSH) verifizieren
- [ ] Push/Pull-Smoke durchfuehren
- [ ] Nachweis + Gate-Status dokumentieren

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus + Endpoint-Erreichbarkeit
- Erfolgreicher Push/Pull-Test gegen Gitea-Remote

## Gate-Status
`Warnung` (initial) -> bei erfolgreicher Verifizierung auf `OK` setzen
```

## 4) Semaphore bereitstellen und Initial-Templates seeden

**Titel**

`Foundation: Semaphore bereitstellen und Initial-Templates seeden`

**Body**

```md
## Kontext
Semaphore ist Schritt 4 der verbindlichen Foundation-Reihenfolge:
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Nach MinIO, PostgreSQL und Gitea wird die Ausfuehrungs- und Pipeline-Schicht benoetigt, um den Betrieb `Semaphore-first` vorzubereiten.

## Ziel
Semaphore in der vorgesehenen LXC-Umgebung bereitstellen, an das kanonische Gitea-Remote anbinden und Initial-Templates fuer wiederholbare Ausfuehrung seeden.

## Vorschlag
- Hook `bootstrap/hooks/040-semaphore.sh` im Plan- und Apply-Modus ausfuehren
- Semaphore-Container auf Ziel-IP/Port starten
- Verbindung zu Gitea (Repo, Credentials/Token) verifizieren
- Basis-Projekt/Inventory/Template fuer Foundation-Run anlegen

## Begruendung
- Schliesst die Foundation-Core-Reihenfolge vollstaendig ab
- Schafft reproduzierbare, dokumentierbare Ausfuehrungspfade
- Legt die Grundlage fuer den spaeteren Standardbetrieb `Semaphore-first`

## Risikoanalyse
- **Warnung:** Fehlkonfiguration bei Gitea-Integration (Webhook/Token/Repo-Zugriff)
- **Warnung:** Template-/Inventory-Parameter nicht konsistent mit `bootstrap.env`
- **Blocker:** Kein erfolgreich ausfuehrbares Initial-Template

## Alternativen
- Manuelle Shell-Ausfuehrung ohne Semaphore (kurzfristig moeglich, aber weniger reproduzierbar)
- Externe CI/CD statt lokaler Semaphore-Instanz (nicht LXC-first)

## Akzeptanzkriterien
- [ ] Semaphore-LXC laeuft stabil (`running`)
- [ ] Web-UI ist auf geplantem Endpoint erreichbar
- [ ] Gitea-Anbindung (Repo-Zugriff) funktioniert
- [ ] Mindestens ein Initial-Template ist angelegt und parameterisiert
- [ ] Testlauf des Templates endet erfolgreich (oder dokumentierte Warnung mit Ursache)
- [ ] Ergebnis/Nachweis im Runtime- oder Betriebsprotokoll dokumentiert
- [ ] Gate-Status fuer dieses Issue gesetzt (`OK|Warnung|Blocker`)

## Tasks
- [ ] Konfiguration in `bootstrap/bootstrap.env` pruefen
- [ ] Hook `040-semaphore.sh` im Plan-Modus pruefen
- [ ] Hook `040-semaphore.sh` im Apply-Modus ausfuehren
- [ ] Gitea-Repo in Semaphore anbinden
- [ ] Initial-Template(s) seeden und Testlauf ausfuehren
- [ ] Nachweis + Gate-Status dokumentieren

## Nachweis
- Command-Log (Plan/Apply)
- Dienststatus + Endpoint-Erreichbarkeit
- Erfolgreiche Repo-Anbindung
- Template-Run-Resultat (Run-ID/Status)

## Gate-Status
`Warnung` (initial) -> bei erfolgreicher Verifizierung auf `OK` setzen
```

## 5) Foundation Core End-to-End validieren

**Titel**

`Foundation Core End-to-End validieren`

**Body**

```md
## Kontext
Die Foundation-Core-Reihenfolge ist verbindlich:
1. MinIO
2. PostgreSQL
3. Gitea
4. Semaphore

Nach den Einzel-Issues pro Dienst wird eine End-to-End-Validierung benoetigt, um den Gesamtpfad als betriebsfaehig nachzuweisen.

## Ziel
Den gesamten Foundation-Core-Fluss technisch und operativ verifizieren, inklusive Abhaengigkeiten, Reihenfolge, Erreichbarkeit, Basisfunktionen und dokumentiertem Gate-Abschluss.

## Scope
- Validierung der 4 Foundation-Core-Dienste in korrekter Reihenfolge
- Querpruefung der Integrationen (Storage, DB, Git-Remote, Orchestrierung)
- Zusammengefuehrter Nachweis fuer Betriebsfreigabe

## Abhaengige Issues
- [ ] #<MinIO-Issue-ID>
- [ ] #<PostgreSQL-Issue-ID>
- [ ] #<Gitea-Issue-ID>
- [ ] #<Semaphore-Issue-ID>

## Vorschlag
- Sequenzielle Verifikation aller Core-Dienste gegen die definierten Akzeptanzkriterien
- Foundation-Smoke ueber `bootstrap/validate.sh` ausfuehren
- Ergebnisse zentral in Runtime-/Betriebsprotokoll zusammenfassen
- Gate-Entscheidung fuer Foundation Core dokumentieren

## Begruendung
- Einzelne erfolgreiche Services garantieren noch keine stabile Gesamtkette
- End-to-End-Nachweis reduziert Betriebsrisiko vor Foundation-Services/Erweiterung
- Schafft klare Freigabebasis fuer nachfolgende Phasen

## Risikoanalyse
- **Warnung:** Integrationsbrueche trotz erfolgreicher Einzel-Smokes
- **Warnung:** Konfigurationsdrift zwischen Hooks und `bootstrap.env`
- **Blocker:** Foundation-Smoke nicht reproduzierbar erfolgreich

## Akzeptanzkriterien
- [ ] Alle 4 Foundation-Core-Issues sind abgeschlossen
- [ ] Reihenfolge MinIO -> PostgreSQL -> Gitea -> Semaphore ist nachweisbar eingehalten
- [ ] `bootstrap/validate.sh --config bootstrap/bootstrap.env` laeuft erfolgreich
- [ ] `smoke-results.jsonl` enthaelt verwertbare Ergebnisse fuer alle Core-Dienste
- [ ] Integrationspfade zeigen keine offenen Blocker
- [ ] Gesamt-Nachweis inkl. Gate-Status ist dokumentiert

## Tasks
- [ ] Abschlussstatus der 4 Einzel-Issues pruefen
- [ ] End-to-End-Validierung ausfuehren
- [ ] Smoke-Artefakte einsammeln und bewerten
- [ ] Rest-Risiken/Warnungen dokumentieren
- [ ] Finalen Gate-Status setzen (`OK|Warnung|Blocker`)

## Nachweis
- Ausfuehrungslog der End-to-End-Validierung
- Ausgabe von `bootstrap/validate.sh`
- `smoke-results.jsonl`
- Kurze Entscheidungsnotiz mit Begruendung des finalen Gate-Status

## Gate-Status
`Warnung` (initial) -> auf `OK` nur bei vollstaendig erfolgreicher, reproduzierbarer End-to-End-Validierung
```