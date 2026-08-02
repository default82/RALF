# Provider 001: PostgreSQL

## Status und Zweck

PostgreSQL ist der erste Referenzprovider des Database Service. Der Provider implementiert die providerneutrale Verwaltungsebene und stellt jedem Consumer seine isolierte [Database Allocation](../contracts/database-allocation-v0.1.md) über das native PostgreSQL-Protokoll bereit.

PostgreSQL ist weder Bestandteil des allgemeinen Database-Service-Vertrags noch eine universelle Datenzugriffs-API oder ein SQL-Proxy. Eine Providerentscheidung gilt immer für eine konkrete Allocation; PostgreSQL ist nicht automatisch für jeden Consumer geeignet.

Ein Deployment kann eine Providerinstanz mit mehreren logischen Allocations oder mehrere Providerinstanzen mit unterschiedlichen Isolationsgrenzen verwenden. Diese Spezifikation trifft noch keine Platzierungs-, Versions- oder Deploymententscheidung und legt nichts an.

## PostgreSQL Provider Instance

Eine **PostgreSQL Provider Instance** ist ein konkret betriebener PostgreSQL-Datenbankserver beziehungsweise Cluster, auf dem null oder mehr Database Allocations liegen können.

Sie besitzt fachlich mindestens:

| Vertragsbegriff | Bedeutung |
| --- | --- |
| `provider_instance_id` | Stabile, deployment-spezifische Referenz der Instanz. |
| `provider_id` | Providerkennung; für diesen Referenzprovider `postgresql`. |
| `deployment_reference` | Nicht geheime Referenz auf die Betriebsumgebung. |
| `version_information` | Explizit festgelegte und nachgewiesene Provider-Version. |
| `capabilities` | Nachgewiesene Fähigkeiten mit Status und Einschränkungen. |
| `lifecycle_status` | Aktueller Providerinstanz-Zustand. |
| `health_status` | Grundsätzliche technische Funktionsfähigkeit. |
| `readiness_status` | Sichere Nutzbarkeit für vorgesehene Allocations. |
| `secret_references` | Nicht geheime Referenzen auf Providergeheimnisse unter `/secrets`. |
| `network_policy_reference` | Referenz auf die erlaubte Netzwerkgrenze. |
| `backup_policy_reference` | Referenz auf providerweite Sicherungsanforderungen, falls vorhanden. |
| `resource_policy_reference` | Referenz auf Kapazitäts- und Ressourcengrenzen. |

Keine konkrete Instanz-ID ist Teil dieses Vertrags.

## Versionsvertrag

- Die Major-Version wird vor Bereitstellung einer Providerinstanz ausdrücklich festgelegt.
- Ein Major-Upgrade besitzt einen eigenen sichtbaren Plan, eine eigene Freigabe und eine anschließende Verifikation.
- Eine Providerinstanz ändert ihre Version niemals stillschweigend.
- Jede Allocation muss mit der gewählten Major-Version und den aktivierten Fähigkeiten kompatibel sein.
- Eine spätere Versionsmatrix berücksichtigt mindestens Sicherheitsstatus, Wartungsstatus und die Anforderungen der Consumer.

Die konkrete Referenzversion bleibt offen.

## Fähigkeiten

### Sicher unterstützt

Der PostgreSQL-Provider kann folgende Fähigkeiten grundsätzlich bereitstellen:

- `relational_storage`
- `transactions`
- `schema_migrations`
- `constraints`
- `indexes`
- `json_documents`
- `full_text_search`
- `advisory_locks`
- `backup`
- `restore`

„Sicher unterstützt“ ersetzt nicht die Prüfung einer konkreten Providerinstanz. Fähigkeiten werden erst für Planungs- und Readinessentscheidungen verwendet, wenn sie für diese Instanz nachgewiesen sind.

### Deployment- oder erweiterungsabhängig

- `point_in_time_recovery`
- `replication`
- `high_availability`
- `vector_search`

`vector_search` darf ausschließlich gemeldet werden, wenn eine geeignete Erweiterung ausdrücklich ausgewählt, installiert und verifiziert wurde. PostgreSQL allein bedeutet nicht, dass Vektorsuche verfügbar ist.

### Fähigkeitsnachweis

Jeder spätere Nachweis enthält mindestens:

- Quelle der Feststellung,
- Provider- und gegebenenfalls Erweiterungsversion,
- Verifikationszeitpunkt,
- Status,
- bekannte Einschränkungen.

Diese Spezifikation implementiert keine technische Probe.

## Providerinstanz-Lebenszyklus

Lese- und Schreibangaben beschreiben die grundsätzliche Zulässigkeit für bestehende Allocations. Deren eigene Readiness bleibt zusätzlich verbindlich.

| Zustand | Bedeutung | Neue Allocations | Bestehende Lesezugriffe | Bestehende Schreibzugriffe | Administrative Aktionen |
| --- | --- | --- | --- | --- | --- |
| `unknown` | Zustand ist nicht verlässlich bekannt. | nein | nein | nein | nur Diagnose und Zustandsklärung |
| `declared` | Bedarf oder vorhandene Instanz ist beschrieben, aber nicht vollständig geplant. | nein | nein | nein | Bestands- und Anforderungsplanung |
| `planned` | Version, Deploymentgrenze und Zielzustand sind geplant; keine Mutation ist erfolgt. | nein | nein | nein | Planprüfung und Freigabe |
| `provisioning` | Die spätere kontrollierte Bereitstellung läuft. | nein | nein | nein | nur der freigegebene Bereitstellungsvorgang |
| `configured` | Provider ist konfiguriert, aber noch nicht betriebsbereit bestätigt. | nein | nein | nein | Prüfung und kontrollierter Start |
| `starting` | Provider startet und wird geprüft. | nein | nein | nein | Startprüfung und Diagnose |
| `ready` | Provider erfüllt die Readinesskriterien. | ja, nach Allocation-Plan | ja, wenn Allocation bereit | ja, wenn Allocation bereit | kontrollierte Provider- und Allocation-Operationen |
| `degraded` | Provider ist grundsätzlich nutzbar, aber mindestens eine Einschränkung besteht. | nur nach sichtbarer Bewertung | abhängig von Einschränkung | abhängig von Einschränkung | Diagnose und begrenzte Korrektur |
| `maintenance` | Geplante Wartung mit ausdrücklich beschriebenen Zugriffsbeschränkungen. | nein | nur wenn der Wartungsplan es erlaubt | nur wenn der Wartungsplan es erlaubt | ausschließlich freigegebene Wartung |
| `stopping` | Kontrolliertes Anhalten läuft. | nein | nein | nein | nur Stop- und Zustandsprüfung |
| `stopped` | Provider ist kontrolliert nicht in Betrieb. | nein | nein | nein | Diagnose, Wartung oder kontrollierter Start |
| `failed` | Sicherer Betrieb ist nicht möglich. | nein | nein | nein | Diagnose und gesondert freigegebene Wiederherstellung |
| `retired` | Providerinstanz ist dauerhaft außer Nutzung; aktive Allocations dürfen nicht verbleiben. | nein | nein | nein | nur Nachweis, Retention und Abschlussprüfung |

Ein Zustandswechsel erfolgt nicht automatisch allein durch den Start eines RALF-Dienstes.

### Kriterien für `ready`

Mindestens:

- PostgreSQL ist grundsätzlich erreichbar,
- eine kontrollierte administrative Provideridentität ist verfügbar,
- die Basiskonfiguration ist konsistent,
- vorhandene Fähigkeiten sind bekannt,
- keine blockierende Wartung läuft,
- der Speicherzustand ist nicht kritisch,
- vorgesehene Allocation-Verbindungen werden akzeptiert.

### Bedeutung von `degraded`

Mögliche Gründe sind knapper Speicher, überfällige Backupprüfung, eine fehlende optionale Fähigkeit oder eine fehlerhafte einzelne Allocation bei grundsätzlich nutzbarem Provider. Grund, Reichweite und erlaubte Zugriffe müssen sichtbar sein.

### Bedeutung von `maintenance`

Es wird keine neue Allocation angelegt. Lese- oder Schreibzugriffe dürfen nur fortbestehen, wenn der konkrete Wartungsplan dies ausdrücklich und sicher erlaubt.

## PostgreSQL-Isolationsvertrag

Referenzstandard ist:

- eine logische PostgreSQL-Datenbank pro Allocation,
- eigene technische Identitäten pro Allocation,
- keine Rechte auf fremde Allocations,
- keine gemeinsame Anwendungsidentität,
- kein gemeinsames Anwendungspasswort,
- kein gemeinsames Anwendungsschema,
- keine Consumer-übergreifenden Anwendungstabellen.

Normale Consumeridentitäten verwalten keine providerweiten administrativen Objekte. Consumer sollen keine unkontrollierten gemeinsamen providerweiten Objekte anlegen können. Die konkrete Behandlung des PostgreSQL-`public`-Schemas wird erst bei der Implementierung festgelegt.

### Dedizierte Providerinstanz

Eine Allocation kann eine eigene Instanz verlangen bei:

- erhöhten Sicherheitsanforderungen,
- unabhängiger Verfügbarkeit,
- inkompatibler PostgreSQL-Major-Version,
- inkompatiblen Erweiterungen,
- stark abweichenden Ressourcenanforderungen,
- besonderen Backup- oder Restorezielen,
- bewusst vermiedener gemeinsamer Fehlerdomäne.

Weder eine gemeinsame noch eine dedizierte Platzierung wird automatisch gewählt.

## Identitätsmodell pro Allocation

| Identität | Sicherheitsziel |
| --- | --- |
| `allocation_owner` | Besitzt zentrale Allocation-Objekte und wird nicht im normalen Anwendungsbetrieb verwendet. |
| `migration_identity` | Darf ausschließlich freigegebene Schemaänderungen durchführen. |
| `application_identity` | Darf ausschließlich normalen fachlichen Anwendungszugriff ausführen. |
| `backup_identity` | Ist auf erforderliche Backup- und Restoreaufgaben begrenzt. |
| `monitoring_identity` | Liest ausschließlich erforderliche Status- und Diagnosedaten. |

Ein Consumer-Profil darf offenlegen, dass Laufzeit und Migration technisch nicht trennbar sind, Backup zentral durch den Provider erfolgt oder eine Identität nicht benötigt wird. Jede Abweichung bleibt sichtbar und wird sicherheitlich bewertet. Normale Anwendungen verwenden niemals eine PostgreSQL-Superuseridentität.

## Verbindlicher Secrets-Vertrag

Alle Datenbankgeheimnisse werden ausschließlich unter `/secrets` gelesen oder abgelegt. Vorgesehene, noch nicht angelegte Referenzstruktur:

```text
/secrets/
└── database-service/
    ├── providers/
    │   └── <provider-instance-id>/
    │       └── ...
    └── allocations/
        └── <allocation-id>/
            ├── owner-password
            ├── migration-password
            ├── application-password
            ├── backup-password
            └── monitoring-password
```

Nicht jede Allocation benötigt jede Datei. Spätere Implementierungen müssen:

- neue Secrets atomar unter `/secrets` schreiben,
- Elternpfade und Dateinamen strikt validieren,
- Traversierung und Auflösung außerhalb `/secrets` verhindern,
- Symlinks ablehnen,
- restriktive Eigentümer und Zugriffsmodi verwenden,
- vorhandene Werte nur durch eine ausdrücklich geplante Rotation ersetzen,
- Secretwerte von Git, Logs, Standardausgabe, Prozessargumenten und normalen Umgebungsvariablen fernhalten,
- in normaler Konfiguration ausschließlich nicht geheime absolute Referenzen speichern.

Providerreferenzen liegen unter `/secrets/database-service/providers/<provider-instance-id>/`; Allocation-Referenzen liegen unter `/secrets/database-service/allocations/<allocation-id>/`.

Ein Plan nennt höchstens die nicht geheime Zielreferenz, niemals Secretwert, Kennworthash oder eine Verbindungsangabe mit Kennwort.

Falls OpenBao später selbst eine PostgreSQL-Allocation verwendet, bezieht es seine Bootstrap-Datenbankgeheimnisse nicht aus sich selbst. `/secrets` bleibt der externe Bootstrap-Vertrauensanker. Das Repository schließt zusätzlich `secrets/` aus.

## Consumer-Profile

### RALF Core

- Typ: `ralf_native`
- Schema-Lebenszyklus: `domain_managed`
- Referenzisolation: `logical_database`
- Pflichtfähigkeiten: `relational_storage`, `transactions`, `schema_migrations`, `constraints`, `indexes`, `backup`, `restore`

### Gitea

- Typ: `external_application`
- Schema-Lebenszyklus: `application_managed`
- Referenzisolation: `logical_database`
- PostgreSQL ist ein möglicher Provider.

Gitea erhält eine eigene Allocation und eigene Identitäten. Version, Datenbankreferenz und Zugangsdaten bleiben offen.

### OpenBao

- Typ: `external_application`
- Schema-Lebenszyklus: `application_managed` oder `platform_preprovisioned`
- PostgreSQL ist eine optionale Storage-Wahl.

Integrated Storage bleibt als Alternative offen. Diese Spezifikation plant keinen OpenBao-Consumer und keine OpenBao-Allocation.

## Health und Readiness

`provider_health` beantwortet, ob die Providerinstanz grundsätzlich technisch funktioniert. `provider_readiness` beantwortet, ob sie im vorgesehenen Vertrag sicher Allocations bedienen kann.

Eine bereite Providerinstanz macht eine Allocation nicht automatisch bereit. Allocation-Health und -Readiness werden unabhängig im [Allocation-Lebenszyklus](../lifecycle/database-allocation.md) bewertet.

## Backup und Restore

Der Referenzstandard ist ein logisches Backup pro Allocation. Providerweite physische Sicherungen können später eine zusätzliche Fähigkeit sein, ersetzen aber nicht automatisch den allocation-bezogenen Vertrag.

Ein Restore für eine Allocation darf niemals stillschweigend andere Allocations oder die gesamte Providerinstanz überschreiben.

## Offene Entscheidungen

1. Welche PostgreSQL-Major-Version wird Referenzversion?
2. Wie wird PostgreSQL in der ersten Referenzumgebung betrieben?
3. Welche Allocations werden im ersten realen Deployment angelegt?
4. Wird zunächst nur RALF Core angelegt?
5. Benötigt Gitea bereits im ersten Deployment eine Allocation?
6. Welches Storage-Backend verwendet OpenBao?
7. Welche Netzwerkgrenze gilt zwischen Consumer und PostgreSQL?
8. Welche Dateieigentümer und Zugriffsmodi gelten unter `/secrets`?
9. Wie erfolgt Secret-Rotation?
10. Welche Ressourcenlimits gelten je Allocation?
11. Wo werden logische Backups gespeichert und wie lange aufbewahrt?
12. Welche Providererweiterungen sind im Basisprofil zulässig?
13. Wie werden PostgreSQL-Major-Upgrades durchgeführt?

**Nächste Entscheidung:** PostgreSQL-Referenzversion, erstes Deploymentprofil und tatsächlich anzulegende Allocations auswählen.
