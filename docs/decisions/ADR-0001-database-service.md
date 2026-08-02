# ADR-0001: Database Service als providerneutrale Datenbankfähigkeit

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

RALF wird von innen nach außen neu entwickelt. Der erste fachliche Baustein soll strukturierte, dauerhafte Datenhaltung ermöglichen, ohne das Gesamtprojekt dauerhaft an ein bestimmtes Datenbankprodukt zu koppeln. PostgreSQL bietet eine belastbare Referenz für Transaktionen, SQL, Rollen, Backup und spätere Erweiterbarkeit. Eine direkte Kopplung anderer RALF-Komponenten an PostgreSQL würde jedoch Providerwechsel, Minimalprofile und klare Verantwortungsgrenzen erschweren.

Zugleich soll die Abstraktion keine künstliche Gleichheit zwischen Datenbankprodukten behaupten. Unterschiedliche Provider besitzen unterschiedliche Fähigkeiten und Sicherheitsmerkmale.

## Entscheidung

Der Database Service ist die persistente Datenbankfähigkeit von RALF. PostgreSQL ist der erste Referenzprovider und bleibt hinter einem fähigkeitsorientierten RALF Database Contract verborgen.

Der öffentliche Vertrag beschreibt Fähigkeiten, Zustände, Schema- und Migrationsprinzipien, Health, Readiness, Backup, Restore, Rollenanforderungen und providerneutrale Fehler. PostgreSQL-spezifische Parameter, SQL-Syntax, Systemtabellen, Erweiterungen, Werkzeuge, Rollenbezeichnungen und Fehlercodes gehören ausschließlich in den PostgreSQL-Provider beziehungsweise seine Betriebs- und Administrationsschicht.

RALF abstrahiert Provider nicht auf einen behaupteten kleinsten gemeinsamen Nenner. Provider deklarieren Fähigkeiten; RALF-Profile und Domänen deklarieren ihre Anforderungen. Fehlt eine Pflichtfähigkeit, ist die Kombination inkompatibel oder eingeschränkt.

Der Database Service wird als Betriebs- und Vertragsdienst ausgelegt. Fachliche Datenmodelle und Datenzugriffe verbleiben in domänenspezifischen Repository-Verträgen. Die fachlichen Begriffe `execute_read` und `execute_write` in Vertrag 0.1 sind daher keine Entscheidung für eine universelle technische Datenzugriffs-API.

## Begründung

- PostgreSQL ermöglicht eine praxistaugliche erste Referenz, ohne den RALF-Vertrag zu definieren.
- Fähigkeiten machen reale Unterschiede zwischen Providern sichtbar.
- Domänenspezifische Repositories behalten Datenmodell und Fachlogik bei der zuständigen Komponente.
- Betriebsaufgaben wie Migration, Health, Backup und Restore erhalten eine klare zentrale Verantwortlichkeit.
- Providerspezifische Diagnose und Werkzeuge können intern vollständig genutzt werden, ohne andere RALF-Komponenten daran zu koppeln.

## Konsequenzen

### Positiv

- Andere Provider bleiben architektonisch möglich.
- Providerinkompatibilität wird explizit statt durch schwache Emulation verborgen.
- PostgreSQL-spezifische Optimierungen können kontrolliert im Provider bleiben.
- Rollen-, Migrations-, Backup- und Restoregrenzen werden früh definiert.
- Es entsteht keine eigene universelle RALF-Datenbanksprache.

### Aufwand und Risiken

- Jede RALF-Domäne muss ihre Datenzugriffsverträge sauber definieren.
- Provider müssen Fähigkeiten und Fehler zuverlässig abbilden.
- Der konkrete Kommunikationsweg zwischen Domänen und Database Service bleibt gesondert zu entscheiden.
- Ein späterer Provider ist nicht automatisch kompatibel; er benötigt einen nachweisbaren Vertragsabgleich.

## Verworfene beziehungsweise nicht gewählte Alternative

Eine allgemeine Datenzugriffsschicht mit universellen Lese- und Schreiboperationen könnte zentrale Kontrolle und einheitliche Fehlerbehandlung vereinfachen. Sie birgt jedoch das Risiko einer künstlichen Universal-API, einer eigenen Datenbanksprache, hoher zentraler Kopplung und des Verlusts sinnvoller nativer Fähigkeiten. Deshalb ist sie nicht das Ziel von Vertrag 0.1.

## Nicht entschiedene Punkte

- erstes fachliches Datenmodell und erster Datenbankkunde,
- konkrete PostgreSQL-Referenzversion und Betriebsform,
- technischer Kommunikationsweg,
- Secrets-Bereitstellung,
- Daten- und Backupspeicherorte,
- Aufbewahrungs- und Verschlüsselungsregeln,
- technische Paketierung von Migrationen,
- konkrete Providerimplementierung und Installation.

Der nächste Schritt ist die Entscheidung, welche fachlichen Daten zuerst gespeichert werden und welche RALF-Komponente dafür als erster Datenbankkunde verantwortlich ist. Er ist ausdrücklich noch keine PostgreSQL-Installation.
