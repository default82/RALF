# ADR-0004: PostgreSQL als erster Referenzprovider

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

ADR-0001 hat den Database Service als providerneutrale Datenbankfähigkeit festgelegt. ADR-0003 hat daraus eine gemeinsam nutzbare Plattform mit isolierten Database Allocations für RALF-native und externe Consumer gemacht. Für die nächste Architekturgrenze benötigt RALF einen ersten konkreten Providervertrag und einen eindeutigen Allocation-Lebenszyklus, ohne bereits Software oder Infrastruktur bereitzustellen.

PostgreSQL kann mehrere logische Datenbanken, getrennte technische Identitäten, transaktionale Schemamigrationen sowie logische Backups und Restores bereitstellen. Eine gemeinsam betriebene Instanz reduziert Betriebsaufwand, bleibt aber eine gemeinsame Fehlerdomäne und ist daher nicht für jeden Consumer zwingend richtig.

## Entscheidung

PostgreSQL ist der erste Referenzprovider des Database Service. Er implementiert die providerneutrale Verwaltungsebene; Consumer greifen auf ihre jeweilige Allocation über das native PostgreSQL-Protokoll zu. Der Database Service ist kein SQL-Proxy und übersetzt keine Anwendungsabfragen.

Der Referenzstandard verwendet eine isolierte logische Datenbank und eigene technische Identitäten pro Allocation. Eine Providerinstanz kann mehrere Allocations tragen; einzelne Allocations können bei begründeten Sicherheits-, Verfügbarkeits-, Versions-, Erweiterungs-, Ressourcen- oder Wiederherstellungsanforderungen eine dedizierte Instanz verlangen.

Alle Datenbankgeheimnisse werden ausschließlich unter `/secrets` verwaltet. Pläne und normale Konfiguration enthalten nur nicht geheime absolute Secret-Referenzen.

Die konkrete PostgreSQL-Major-Version, das Deploymentprofil und die ersten tatsächlich anzulegenden Allocations werden separat entschieden.

## Spätere Präzisierung

[ADR-0005](ADR-0005-first-postgresql-deployment-profile.md) wählt für die erste Referenzumgebung PostgreSQL Major 18, die Providerinstanz `postgresql-main` und vier isolierte Allocations. Diese deployment-spezifische Auswahl ändert weder die Providerneutralität noch die Möglichkeit anderer Platzierungen.

## Begründung

- PostgreSQL bildet die für die ersten Consumer benötigten relationalen und transaktionalen Fähigkeiten belastbar ab.
- Logische Datenbanken und getrennte Identitäten schaffen eine verständliche Referenzisolation.
- Native Providerzugriffe erhalten die Datenmodelle und Migrationswege externer Anwendungen.
- Ein expliziter Provider- und Allocation-Lebenszyklus verhindert stille Bereitstellung oder Migration beim Dienststart.
- Eine optionale dedizierte Platzierung macht Sicherheits- und Fehlerdomänenanforderungen sichtbar.
- Die Providerneutralität des allgemeinen Database-Service-Vertrags bleibt bestehen.

## Konsequenzen

### Positive Folgen

- RALF Core, Gitea und weitere Consumer können getrennte Allocations erhalten.
- Provider- und Allocation-Status werden unabhängig bewertet.
- Fähigkeiten werden für die konkrete Instanz nachgewiesen statt aus dem Produktnamen abgeleitet.
- Backup, Restore, Migration, Secret-Rotation und Löschung besitzen getrennte Plan- und Freigabegrenzen.
- Eine spätere zweite Providerimplementierung muss denselben providerneutralen Verwaltungsvertrag erfüllen.

### Aufwand und Risiken

- Eine gemeinsam genutzte Instanz bleibt eine gemeinsame Fehler- und Ressourcendomäne.
- Isolation, minimale Rechte und fehlende Fremdzugriffe müssen später technisch verifiziert werden.
- Consumer mit anwendungseigenen Migrationen können abweichende Identitätsmodelle benötigen.
- Major-Upgrades, Erweiterungen, Ressourcenlimits und Netzwerkgrenzen benötigen eigene Pläne.
- Providerweite Sicherungen und allocation-bezogene Restores müssen klar getrennt bleiben.

## Sicherheitsfolgen

- Jede Allocation erhält eigene technische Identitäten und Secret-Referenzen.
- Consumer erhalten keine Rechte auf fremde Allocations und verwenden keine PostgreSQL-Superuseridentität.
- Gemeinsame Anwendungskonten, Kennwörter, Anwendungsschemata und Consumer-übergreifende Anwendungstabellen sind ausgeschlossen.
- Providerweite administrative Objekte bleiben außerhalb normaler Consumeridentitäten.
- `vector_search` wird nur bei ausdrücklich installierter und verifizierter Erweiterung gemeldet.
- Eine dedizierte Providerinstanz bleibt für höhere Isolationsanforderungen möglich.

## Secrets-Vertrag

`/secrets` ist die einzige kanonische externe Secrets-Wurzel. Provider- und Allocation-Geheimnisse liegen unter getrennten, strikt validierten Pfaden; Repository und Pläne enthalten nur Referenzen. Werte erscheinen weder in Git, Logs, Standardausgabe, Prozessargumenten noch normalen Umgebungsvariablen und werden nicht automatisch überschrieben.

OpenBao ersetzt diesen Bootstrap-Vertrauensanker nicht automatisch. Falls OpenBao eine PostgreSQL-Allocation erhält, werden seine eigenen Bootstrap-Datenbankgeheimnisse nicht zirkulär aus OpenBao bezogen.

## Verworfene und zurückgestellte Alternativen

### Eine gemeinsame Datenbank für alle Consumer

Verworfen wegen fehlender Daten-, Schema-, Rechte- und Restoreisolation.

### Ein gemeinsames Anwendungskonto

Verworfen, weil minimale Rechte und nachvollziehbare Zugriffe pro Allocation nicht gewährleistet wären.

### Database Service als SQL-Proxy

Verworfen, weil dies native Treiber und Datenmodelle durch eine künstliche Universal-API ersetzen würde.

### PostgreSQL-Superuser für Anwendungen

Verworfen, weil normale Consumer keine providerweiten Administrationsrechte benötigen.

### Secrets im Repository

Verworfen; das Repository enthält ausschließlich nicht geheime Referenzen.

### Secrets ausschließlich in OpenBao

Zurückgestellt, weil OpenBao selbst Database Consumer sein kann und dadurch eine zirkuläre Bootstrap-Abhängigkeit entstünde.

### Sofort eine dedizierte Instanz pro Consumer

Verworfen als zwingender Standard, weil dies ohne konkreten Isolationsbedarf unnötigen Betriebsaufwand erzeugt.

### Sofort alle Consumer auf einer gemeinsamen Instanz

Verworfen als Zwang, weil Sicherheits-, Verfügbarkeits-, Versions-, Erweiterungs- oder Ressourcenanforderungen eine Trennung verlangen können.

## Offene Punkte

- technische Verifikation der in ADR-0005 gewählten Referenzversion und Wartungsmatrix,
- technische Umsetzung des in ADR-0005 gewählten Deploymentprofils,
- Netzwerkgrenzen zwischen Consumern und Provider,
- Eigentümer- und Zugriffsmodell unter `/secrets`,
- Secret-Rotation,
- Ressourcenlimits und Platzierungskriterien,
- Backupziel, Retention und providerweite Sicherungen,
- zulässige Erweiterungen,
- Major-Upgradeverfahren,
- konkrete Behandlung providerweiter Standardobjekte.

## Nächster Schritt

ADR-0005 beantwortet Versions-, Profil- und Allocation-Auswahl; ADR-0006 konkretisiert das Laufzeitprofil. Der [read-only Deploymentplan](../operations/postgresql-main-deployment-plan.md) validiert diese Entscheidungen, ohne Infrastruktur zu verändern. Als Nächstes wird ein eigener Apply-Vertrag mit sichtbaren Mutationen, Recovery-Grenzen und separater Freigabe spezifiziert. PostgreSQL, Datenbanken, Identitäten, Secrets und Netzwerkfreigaben bleiben bis zu einem solchen bestätigten Apply unverändert.
