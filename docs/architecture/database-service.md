# Dienst 001: Database Service – Architektur

## Zweck

Der Database Service ist eine gemeinsam nutzbare Datenbankplattform. Er verwaltet einen oder mehrere Datenbankprovider und deren Providerinstanzen und stellt daraus voneinander isolierte Datenbankzuweisungen für RALF-eigene Komponenten, externe Anwendungen und spätere interne Plattformkomponenten bereit.

PostgreSQL ist der erste Referenzprovider, aber kein Bestandteil des öffentlichen RALF-Vertrags. Ein Consumer ist weder Eigentümer des Database Service noch automatisch Eigentümer einer Providerinstanz. RALF Core ist der erste spezifizierte RALF-native Consumer, nicht der einzige Datenbankkunde.

## Architekturmodell

```text
                         Database Service
                 ┌─────────────────────────────┐
                 │ Verwaltungsebene            │
                 │                             │
                 │ Providerinstanzen           │
                 │ Database Allocations        │
                 │ Identitäten / Secret-Refs   │
                 │ Fähigkeiten                 │
                 │ Health / Readiness          │
                 │ Backup / Restore            │
                 └──────────────┬──────────────┘
                                │
                       PostgreSQL-Provider
                                │
          ┌─────────────────────┼─────────────────────┐
          │                     │                     │
          ▼                     ▼                     ▼
  Allocation RALF Core    Allocation Gitea     Allocation OpenBao
          │                     │                     │
 ConversationRepository   Gitea-eigener       OpenBao-eigener
 PostgreSQL-Adapter       Datenbankzugriff     Storage-Zugriff
```

Das Modell beschreibt mögliche isolierte Zuweisungen, keine bereits laufende Installation. [ADR-0005](../decisions/ADR-0005-first-postgresql-deployment-profile.md) wählt für das erste Referenzdeployment Gitea, OpenBao, Semaphore UI und Node-RED als vier isolierte Allocations; eingerichtet ist davon noch keine.

## Verwaltungs- und Datenebene

### Verwaltungsebene

Der providerneutrale Database-Service-Vertrag beschreibt Providerinstanzen, Database Allocations, Fähigkeiten, Isolation, technische Identitäten, Secret-Referenzen, Lebenszyklus, Health, Readiness, Backup, Restore sowie Versions- und Kompatibilitätsstatus.

Diese Ebene ist für RALF steuerbar. Sie plant und bewertet Zustände, ohne Anwendungsabfragen zu übersetzen.

### Datenebene

Anwendungen greifen später über das native Datenbankprotokoll des ausgewählten Providers direkt auf ihre eigene Allocation zu. Für PostgreSQL ist dies das PostgreSQL Wire Protocol.

Der Database Service ist kein SQL-Proxy, übersetzt keine Anwendungsabfragen und stellt keine universelle CRUD-API bereit.

RALF-native Consumer verwenden weiterhin domänenspezifische Repository-Verträge und einen providerbezogenen Infrastrukturadapter. Externe Anwendungen verwenden ihre eigenen Datenbanktreiber, Datenmodelle und Schemata. Der Database Service versucht insbesondere nicht, das Datenmodell von Gitea oder OpenBao in einen RALF-Domänenvertrag zu übersetzen.

## Database Consumer

Ein **Database Consumer** ist eine Anwendung oder RALF-Komponente, die eine isolierte Datenbankzuweisung benötigt.

| Consumer-Art | Bedeutung | Beispiele |
| --- | --- | --- |
| `ralf_native` | RALF-eigene Komponente mit domänenspezifischem Repository-Vertrag. | RALF Core |
| `external_application` | Fremde Anwendung, die den Provider nativ verwendet und ihr eigenes Schema verantwortet. | Gitea, optional OpenBao |
| `platform_internal` | Spätere technische Plattformkomponente ohne eigene fachliche RALF-Domäne. | noch nicht festgelegt |

Ein Consumer-Profil beschreibt Anforderungen einer Anwendung, aber keine laufende Installation.

## Database Allocation

Eine **Database Allocation** ist eine isolierte Zuweisung von Datenbankressourcen an genau einen Consumer. Der fachliche Vertrag umfasst mindestens:

- `allocation_id`
- `consumer_id`
- `provider_instance_id`
- `database_name_reference`
- `isolation_class`
- `schema_lifecycle`
- `required_capabilities`
- `optional_capabilities`
- `identity_references`
- `secret_references`
- `backup_policy_reference`
- `retention_policy_reference`
- `status`

Diese Namen sind Vertragsbegriffe und weder Konfigurationsschema noch Datenbankobjekte.

### Referenzisolation

Für den ersten PostgreSQL-Referenzstand gilt als Standard:

- eine logische Datenbank pro Consumer,
- eigene technische Identitäten pro Consumer,
- keine Rechte auf Datenbanken anderer Consumer,
- keine gemeinsam genutzten Anwendungsschemata, insbesondere kein gemeinsames `public`-Schema.

Nicht vorgesehen sind eine gemeinsame Datenbank oder ein gemeinsames Anwendungsschema für alle Consumer, eine gemeinsame Anwendungsidentität oder ein gemeinsames Kennwort.

### Isolationsklassen

| Klasse | Bedeutung |
| --- | --- |
| `logical_database` | Eigene logische Datenbank innerhalb einer gemeinsam betriebenen Providerinstanz. |
| `dedicated_provider_instance` | Eigene Providerinstanz aufgrund von Sicherheits-, Verfügbarkeits- oder Kompatibilitätsanforderungen. |
| `external_provider` | Bereits vorhandene externe Datenbankbereitstellung, die der Database Service kontrolliert referenziert oder verwaltet. |

Version 0.1 darf eine gemeinsame PostgreSQL-Providerinstanz mit mehreren logischen Datenbanken als Referenzprofil beschreiben. Jede Allocation verwendet genau einen aktiven Provider; die Architektur erlaubt später die Verlagerung einzelner Allocations auf dedizierte oder externe Providerinstanzen.

## Gemeinsame Fehlerdomäne und Platzierung

Eine gemeinsame Providerinstanz reduziert Betriebsaufwand, vergrößert aber die gemeinsame Fehlerdomäne. Ein Providerausfall kann mehrere Consumer gleichzeitig betreffen.

Jede Allocation muss deshalb später Anforderungen an Verfügbarkeit, Isolation, Ressourcen, Backup und Restore deklarieren können:

- `availability_requirement`
- `isolation_requirement`
- `resource_requirement`
- `backup_requirement`
- `restore_requirement`

Ein sicherheitskritischer Consumer darf eine dedizierte Instanz verlangen. Version 0.1 trifft keine automatische Platzierungsentscheidung.

## Schemaeigentum

Jede Allocation besitzt genau einen sichtbaren Schema-Lebenszyklus:

| Modus | Eigentum und Ablauf |
| --- | --- |
| `domain_managed` | Eine RALF-Domäne besitzt fachlich Schema und Migrationen. Der Database Service plant, prüft Providerfähigkeiten und führt freigegebene Migrationspakete aus. |
| `application_managed` | Eine externe Anwendung besitzt Schema und Migrationen und führt sie nach ihrem Betriebsmodell aus. Der Database Service beansprucht keine fachliche Eigentümerschaft. |
| `platform_preprovisioned` | Die Plattform legt ausdrücklich vertraglich verlangte Datenbankobjekte kontrolliert vor dem Anwendungsstart an. |

RALF Core mit Conversation verwendet `domain_managed`. Gitea verwendet als mögliches Profil `application_managed`. Für OpenBao bleiben `application_managed` und `platform_preprovisioned` abhängig vom später gewählten Storage-Vertrag zu prüfen.

Wenn eine externe Anwendung beim Start selbst migriert, muss ihr Consumer-Vertrag sichtbar festlegen, ob eine getrennte Migrationsidentität möglich ist, wann erweiterte Rechte benötigt werden, ob Laufzeit und Migration dieselbe Identität verwenden und ob Rechte anschließend reduziert werden können. Die RALF-native Regel „Anwendungsidentität ändert kein Schema“ wird auf externe Anwendungen nicht ungeprüft übertragen.

## Consumer-Profile

Ein **Database Consumer Profile** beschreibt Anforderungen, ohne eine Installation oder Allocation anzulegen. Es enthält mindestens:

- `consumer_profile_id`
- `consumer_type`
- `supported_provider_ids`
- `required_capabilities`
- `optional_capabilities`
- `schema_lifecycle`
- `identity_model`
- `backup_expectations`
- `health_expectations`
- `known_constraints`

### RALF Core

`ralf-core` ist ein `ralf_native`-Profil mit `domain_managed`. Conversation benötigt `relational_storage`, `transactions`, `schema_migrations`, `constraints`, `indexes`, `backup` und `restore`. Der [ConversationRepository Contract](../contracts/conversation-repository-v0.1.md) gilt ausschließlich für die RALF-Core-Allocation.

### Gitea

Gitea ist ein möglicher `external_application`-Consumer und unterstützt PostgreSQL als Datenbankbackend. Sein Profil verwendet `application_managed` und verlangt eine eigene logische Datenbank, eigene technische Identitäten und keine Rechte auf andere Allocations. Version, Provider-Mindestversion, Konfiguration, Schema, Migrationen und Installation bleiben offen.

### OpenBao

OpenBao ist ein möglicher `external_application`-Consumer. Sein PostgreSQL-Backend gilt als produktions- und HA-fähige Storage-Option; für andere Installationen bleibt Integrated Storage ein gleichwertig zu prüfender Kandidat. ADR-0005 wählt PostgreSQL ausschließlich für das erste Referenzdeployment. Eigene logische Datenbank, eigene Identitäten und fehlende Rechte auf andere Allocations bleiben Pflicht.

## Identitäten und Rollen pro Allocation

Rollen und Identitäten werden pro Allocation betrachtet:

- `allocation_owner`
- `migration_identity`
- `application_identity`
- `backup_identity`
- `monitoring_identity`

Der frühere Begriff `database_owner` bezeichnet präzisiert den Provider- oder Allocation-Eigentümer und wird nie automatisch von einer Anwendung verwendet.

Jede Allocation besitzt eigene Identitäten. Gemeinsame Anwendungsidentitäten oder Kennwörter, Zugriff auf fremde Datenbanken und PostgreSQL-Superuseridentitäten für Consumer sind unzulässig. Consumer-Profile dürfen ausdrücklich erklären, dass keine getrennte Migrationsidentität unterstützt wird oder Backup beziehungsweise Monitoring zentral erfolgt; Abweichungen bleiben sichtbar.

## Secrets-Vertrag

Die verbindliche externe Secrets-Wurzel ist absolut:

```text
/secrets/
└── database-service/
    ├── providers/
    │   └── <provider-instance-id>/
    └── allocations/
        └── <allocation-id>/
```

Spätere Allocation-Dateien können `owner-password`, `migration-password`, `application-password`, `backup-password` oder `monitoring-password` heißen; nicht jede Allocation benötigt jede Datei. Diese Struktur ist ein Vertrag und wird hier nicht angelegt.

Normale Konfiguration enthält nur nicht geheime absolute Referenzen, beispielsweise:

```text
secret_ref = "/secrets/database-service/allocations/gitea/application-password"
```

Kennwortwerte und vollständige Verbindungs-URLs mit Zugangsdaten sind ausgeschlossen.

Später erzeugte Geheimnisse werden ausschließlich unter `/secrets` atomar und mit restriktiven Rechten geschrieben. Sie erscheinen weder in stdout, Logs, Kommandozeilenargumenten noch normalen Umgebungsvariablen, gelangen nicht in Git und werden nur durch einen ausdrücklich geplanten Rotationsvorgang ersetzt.

Secret-Referenzen müssen absolute Pfade innerhalb `/secrets` sein, dürfen kein `..` und keine Auflösung außerhalb der Wurzel enthalten, keine unerwarteten Symlinks nutzen und ohne bewusstes Anwendungs-Gruppenmodell weder gruppen- noch weltlesbar sein.

Das Repository behält zusätzlich den Ausschluss `secrets/`. Weder `/secrets` noch ein lokales `secrets/` darf committed oder gestaged werden.

OpenBao kann später als Secrets-Provider untersucht werden, ersetzt `/secrets` aber nicht automatisch. Falls OpenBao selbst eine PostgreSQL-Allocation verwendet, dürfen seine Bootstrap-Datenbankgeheimnisse nicht zirkulär aus OpenBao stammen. `/secrets` bleibt zunächst der externe Bootstrap-Vertrauensanker; eine Migration anderer Geheimnisse zu OpenBao benötigt eine eigene Entscheidung und einen eigenen Plan.

## Health und Readiness

Health und Readiness werden getrennt für Providerinstanz und Allocation gemeldet:

- `provider_health`
- `provider_readiness`
- `allocation_health`
- `allocation_readiness`

Ein Zustand kann beispielsweise gleichzeitig „Provider bereit“, „Gitea-Allocation bereit“, „RALF-Core-Allocation `migration_required`“ und „OpenBao-Allocation `unconfigured`“ lauten. Ein Fehler einer Allocation wird nicht automatisch als Fehler aller Allocations dargestellt.

Allocation-Readiness verlangt mindestens eine bereite Providerinstanz, vorhandene logische Datenbank, benötigte Fähigkeiten, auflösbare Secret-Referenzen, verwendbare technische Identität, erwarteten Schemazustand, einen erforderlichen Backupvertrag und den Ausschluss fremder Zugriffsrechte.

## Backup und Restore

Version 0.1 beschreibt Backups mindestens allocation-bezogen. Jedes Backup gehört eindeutig zu `provider_instance_id`, `allocation_id` und `consumer_id`. Fachlicher Standard ist ein logisches Backup pro Allocation.

Ein Restore einer Allocation darf keine andere Allocation oder die gesamte Providerinstanz stillschweigend überschreiben. Providerweite physische Sicherungen können später zusätzlich geplant werden.

Bei OpenBao hängt der Backupvertrag vom deployment-spezifisch gewählten Storage-Backend ab. Integrated Storage liegt außerhalb des PostgreSQL-Database-Service-Backups; die in ADR-0005 gewählte PostgreSQL-Allocation fällt unter den Allocation-Backupvertrag.

## Providerprinzip

RALF abstrahiert Datenbankprodukte nicht auf den kleinsten gemeinsamen Nenner. Provider deklarieren Fähigkeiten; Consumer-Profile und Allocations deklarieren Anforderungen. Fehlende Pflichtfähigkeiten führen nachvollziehbar zu Inkompatibilität oder Einschränkung. Zusätzliche Providerfähigkeiten werden nicht automatisch allgemeiner Vertragsbestandteil.

Andere RALF-Komponenten dürfen keine PostgreSQL-Systemtabellen, Erweiterungen, SQL-Dialekte, Fehlermeldungen, Rollen oder Werkzeuge voraussetzen. Externe Anwendungen dürfen den von ihnen ausdrücklich unterstützten Provider nativ verwenden, ohne dass ihre Fachmodelle Teil des RALF-Vertrags werden.

## Nicht-Verantwortlichkeiten

Der Database Service ist kein SQL-Proxy, allgemeiner CRUD-Dienst, Datei- oder Objekt-Storage, Cache, Message Queue, Event Bus, Suchdienst, Vektorspeicher oder Secrets-Provider. Er verwaltet weder fremde Anwendungsfachmodelle noch Modellinferenz, Benutzeroberflächen, Reverse Proxy, Netzwerk, Container, Proxmox oder OPNsense.

## PostgreSQL als Referenzprovider

PostgreSQL ist als [Provider 001](../providers/postgresql.md) der erste konkrete Referenzprovider. Eine PostgreSQL Provider Instance ist ein betriebener Server beziehungsweise Cluster mit null oder mehr isolierten Allocations. Providerinstanz und Allocation besitzen getrennte [Lebenszyklen](../lifecycle/database-allocation.md); eine bereite Instanz macht eine einzelne Allocation nicht automatisch bereit.

Der Referenzstandard verwendet eine logische Datenbank und eigene technische Identitäten pro Allocation. ADR-0005 legt PostgreSQL Major 18, die 18.x-Minor-Policy, `postgresql-main` und vier initiale Allocations fest. Paketquelle, Betriebsform, Netzwerkgrenze, Serverkonfiguration, konkrete Datenbanknamen, PostgreSQL-Benutzernamen, Port, Adresse und Secretwerte bleiben bis zum Folgeplan offen. [ADR-0004](../decisions/ADR-0004-postgresql-reference-provider.md) und ADR-0005 halten diese Grenzen fest.

## Offene Entscheidungen

1. Welche Consumer benötigen später eine dedizierte Providerinstanz?
2. Welche externen Anwendungen führen Migrationen selbst aus?
3. Wie erhalten Anwendungen Zugriff auf ihre Secrets unter `/secrets`?
4. Welche Eigentümer- und Gruppenrechte gelten unter `/secrets`?
5. Wie erfolgt Secret-Rotation?
6. Welche Backups erfolgen pro Allocation und welche providerweit?
7. Wie werden Ressourcenlimits pro Allocation abgebildet?
8. Welche Netzwerkgrenzen gelten zwischen Consumer und Provider?
9. Wie wird das in ADR-0005 gewählte Profil konkret betrieben und read-only geplant?

**Nächster kleiner Schritt:** Einen ausschließlich read-only arbeitenden Deploymentplan für PostgreSQL 18, `postgresql-main` und die vier ausgewählten Allocations erstellen.
