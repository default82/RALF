# ADR-0003: Database Service als gemeinsam nutzbare Datenbankplattform

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

ADR-0001 hat den Database Service als providerneutrale Datenbankfähigkeit definiert. ADR-0002 hat RALF Core und Conversation als ersten fachlich spezifizierten Kunden beschrieben. Diese Formulierungen konnten den falschen Eindruck erzeugen, der Database Service sei ausschließlich ein Persistenzdienst für RALF Core oder besitze genau eine RALF-Datenbank.

RALF soll jedoch vorhandene und neue Datenbankbedarfe mehrerer Anwendungen kontrolliert bündeln können. Neben RALF Core können beispielsweise Gitea, OpenBao oder spätere Plattformkomponenten einen relationalen Datenbankprovider benötigen. Ihre Datenmodelle, Migrationsregeln und Sicherheitsanforderungen unterscheiden sich.

## Entscheidung

Der Database Service ist eine gemeinsam nutzbare Datenbankplattform. Er verwaltet eine oder mehrere Providerinstanzen und stellt voneinander isolierte **Database Allocations** für RALF-native Consumer, externe Anwendungen und spätere interne Plattformkomponenten bereit.

PostgreSQL bleibt der erste Referenzprovider. Eine Allocation verwendet genau einen aktiven Provider und gehört genau einem Consumer. Referenzstandard ist eine eigene logische Datenbank mit eigenen technischen Identitäten je Consumer innerhalb einer gemeinsam betriebenen PostgreSQL-Providerinstanz. Dedizierte oder externe Providerinstanzen bleiben möglich.

RALF Core ist der erste spezifizierte RALF-native Consumer, aber weder einziger Datenbankkunde noch Eigentümer des Database Service oder der PostgreSQL-Instanz.

Die providerneutrale Verwaltungsebene beschreibt Provider, Allocations, Isolation, Identitäts- und Secret-Referenzen, Fähigkeiten, Lifecycle, Health, Readiness, Backup und Restore. Die Datenebene verwendet das native Providerprotokoll. Der Database Service ist kein SQL-Proxy und keine universelle CRUD-API.

RALF-native Domänen verwenden eigene Repository-Verträge und Infrastrukturadapter. Externe Anwendungen wie Gitea oder optional OpenBao verwenden ihre nativen Datenbanktreiber und eigenen Schemata. Ihre Fachmodelle werden nicht in RALF-Verträge übersetzt.

## Begründung

- Gemeinsamer Providerbetrieb kann Betriebsaufwand reduzieren, ohne Daten und Rechte gemeinsam zu machen.
- Allocations machen Consumer, Isolation, Schemaeigentum, Identitäten, Backups und Restoreziele explizit.
- Externe Anwendungen können native, von ihnen unterstützte Datenbankzugriffe behalten.
- RALF-native Domänen behalten fachliche Repository-Grenzen.
- Einzelne sicherheitskritische oder inkompatible Consumer können später dediziert platziert werden.
- Providerneutralität bleibt erhalten, während PostgreSQL eine konkrete Referenz bildet.

## Konsequenzen

### Positive Folgen

- Mehrere Consumer können denselben Plattformdienst kontrolliert nutzen.
- Eine logische Datenbank pro Consumer ist ein klarer Referenzstandard.
- Schema-, Identitäts-, Backup- und Restoreverantwortung wird allocation-bezogen sichtbar.
- Gitea, OpenBao und andere Anwendungen müssen keine RALF-Domänen-API übernehmen.
- RALF Core und Conversation bleiben unverändert fachlich abgegrenzt.

### Aufwand und Risiken

- Provider- und Allocation-Lebenszyklen müssen getrennt modelliert werden.
- Eine gemeinsame Providerinstanz bleibt eine gemeinsame Fehlerdomäne.
- Consumer-Profile müssen Migrations- und Identitätsbesonderheiten offenlegen.
- Ressourcen-, Netzwerk- und Backupisolation benötigen spätere konkrete Verträge.
- OpenBao benötigt eine bewusste Storage- und Bootstrap-Secrets-Entscheidung.

## Sicherheitsfolgen

- Jede Allocation erhält eigene technische Identitäten und Secret-Referenzen.
- Consumer erhalten keine Rechte auf fremde Allocations.
- Gemeinsame Anwendungskonten, Kennwörter und Anwendungsschemata sind ausgeschlossen.
- Consumer verwenden keine PostgreSQL-Superuseridentität.
- Eine externe Anwendung mit anwendungseigenen Migrationen muss erweiterte Rechte und deren zeitliche Begrenzung ausdrücklich deklarieren.
- Restore und Löschung werden allocation-bezogen geplant und dürfen fremde Allocations nicht stillschweigend verändern.
- Sicherheitskritische Consumer können eine dedizierte Providerinstanz verlangen.

## Secrets-Vertrag

Die absolute Wurzel `/secrets` bleibt der verbindliche externe Bootstrap-Vertrauensanker. Provider- und Allocation-Geheimnisse liegen ausschließlich darunter; normale Konfiguration speichert nur nicht geheime Referenzen. Das Repository behält `secrets/` als Ausschluss.

OpenBao kann später als Secrets-Provider untersucht werden, ersetzt `/secrets` aber nicht automatisch. Nutzt OpenBao selbst eine Database Allocation, dürfen die zum Start dieser Allocation notwendigen Geheimnisse nicht zirkulär aus OpenBao bezogen werden. Eine spätere Migration anderer Geheimnisse ist eine eigene Entscheidung mit eigenem Plan.

## Verworfene und zurückgestellte Alternativen

### Eine gemeinsame RALF-Datenbank

Verworfen, weil externe Anwendungen eigene Datenbanken, Schemata und Lebenszyklen benötigen und nicht Eigentum einer RALF-Domäne werden.

### Universeller Datenzugriffsproxy

Verworfen, weil Gitea, OpenBao und andere Anwendungen ihre nativen Treiber und Datenmodelle verwenden. Ein Proxy würde Abfrageübersetzung, zusätzliche Fehlerbilder und eine künstliche Universal-API schaffen.

### Gemeinsames Schema für alle Consumer

Verworfen wegen fachlicher Kopplung, Sicherheitsrisiken und unkontrollierbarer Backup- und Restoreauswirkungen.

### Gemeinsame technische Identität

Verworfen, weil Rechte nicht minimal begrenzbar und Zugriffe nicht sauber nachvollziehbar wären.

### OpenBao sofort als einziger Secrets-Speicher

Zurückgestellt, weil OpenBao als eigener Database Consumer eine zirkuläre Bootstrap-Abhängigkeit erzeugen könnte und `/secrets` ausdrücklich der bestehende externe Vertrauensanker bleibt.

## Offene Punkte

- erste tatsächlich anzulegende Allocations,
- RALF-Core-only oder zusätzlich Gitea im ersten Referenzdeployment,
- OpenBao Integrated Storage oder PostgreSQL,
- Kriterien für dedizierte Providerinstanzen,
- Behandlung anwendungseigener Migrationen,
- Zugriff und Rechte unter `/secrets`,
- Secret-Rotation,
- allocation- und providerweite Backups,
- Ressourcen- und Netzwerkgrenzen,
- PostgreSQL-Referenzversion.

## Nächster Schritt

[ADR-0004](ADR-0004-postgresql-reference-provider.md) hat PostgreSQL als ersten konkreten Referenzprovider sowie die getrennten Provider- und Allocation-Lebenszyklen festgelegt. Als Nächstes werden PostgreSQL-Referenzversion, erstes Deploymentprofil und tatsächlich anzulegende Allocations ausgewählt. Es wird noch keine PostgreSQL-Instanz, Datenbank, Identität oder Allocation angelegt.
