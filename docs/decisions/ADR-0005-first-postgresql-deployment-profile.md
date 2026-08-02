# ADR-0005: Erstes PostgreSQL-Deploymentprofil

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

ADR-0004 definiert PostgreSQL als ersten Referenzprovider, lässt jedoch Major-Version, Instanzprofil und erste Allocations offen. Für einen späteren reproduzierbaren Implementierungsplan müssen diese Auswahlentscheidungen feststehen, ohne bereits PostgreSQL, Datenbanken, Identitäten, Rollen oder Secrets anzulegen.

Die erste Referenzumgebung benötigt Datenbankzuweisungen für Gitea, OpenBao, Semaphore UI und relationale Anwendungsdaten von Node-RED. RALF Core ist noch nicht implementiert und besitzt noch kein konkretes Schema oder Migrationspaket.

## Entscheidung

### PostgreSQL-Version

- Referenz-Major-Version ist PostgreSQL **18**.
- Initial dokumentierter Minor-Stand ist **18.4**.
- Zum späteren Installationszeitpunkt wird die neueste stabile **18.x**-Minor-Version ausgewählt.
- 18.4 ist kein dauerhaft festgeschriebener Installationsstand.
- Ein automatischer Wechsel auf PostgreSQL 19 ist ausgeschlossen.
- Jedes Major-Upgrade benötigt einen eigenen Plan und eine eigene ausdrückliche Freigabe.

### Providerinstanz

| Begriff | Auswahl |
| --- | --- |
| `provider_instance_id` | `postgresql-main` |
| Provider | PostgreSQL |
| `isolation_profile` | `shared-provider-with-isolated-logical-databases` |

Eine gemeinsame Providerinstanz trägt zunächst vier voneinander isolierte logische Database Allocations. Diese Platzierung ist Referenzprofil, kein Zwang für andere Deployments oder spätere erhöhte Isolationsanforderungen.

### Erste Allocations

| `allocation_id` | Consumer | `consumer_type` | `isolation_class` | `schema_lifecycle` | Auswahl und Zweck |
| --- | --- | --- | --- | --- | --- |
| `gitea` | Gitea | `external_application` | `logical_database` | `application_managed` | `selected: true` |
| `openbao` | OpenBao | `external_application` | `logical_database` | `application_managed` | `selected: true`, `sensitivity: high` |
| `semaphore` | Semaphore UI | `external_application` | `logical_database` | `application_managed` | `selected: true` |
| `nodered` | Node-RED | `external_application` | `logical_database` | `application_managed` | `selected: true`, `purpose: flow_application_data` |

Logische Datenbanknamen und konkrete PostgreSQL-Benutzernamen werden noch nicht festgelegt.

## OpenBao-Storage

PostgreSQL ist für OpenBao in dieser Referenzumgebung bewusst als Storage ausgewählt. Diese Wahl ist deployment-spezifisch und macht PostgreSQL nicht zum allgemeinen Pflicht-Storage für OpenBao. Integrated Storage bleibt für andere Installationen eine zulässige Alternative.

Die als hochsensibel eingestufte OpenBao-Allocation kann später bei nachgewiesenem Bedarf auf eine dedizierte Providerinstanz verlagert werden. Eine solche Änderung benötigt einen eigenen Plan.

OpenBao bezieht seine Bootstrap-Datenbankgeheimnisse nicht aus sich selbst. `/secrets` bleibt der externe Bootstrap-Vertrauensanker.

## Node-RED-Abgrenzung

Die Node-RED-Allocation dient ausschließlich relationalen Daten von Node-RED-Flows. Sie wird nicht automatisch zum internen Node-RED-Storage.

Flowdateien, Credentials und Context bleiben zunächst außerhalb dieser Allocation. Eine spätere Änderung des Node-RED-Storage-Vertrags benötigt eine eigene Entscheidung.

## RALF Core

RALF Core erhält im ersten realen Deployment noch keine Allocation. Seine Allocation wird erst angelegt, wenn Core implementiert ist und ein konkretes fachliches Schema beziehungsweise Migrationspaket vorliegt. Die frühere Entscheidung, RALF Core als ersten spezifizierten RALF-nativen Consumer zu behandeln, bleibt davon unberührt.

## Isolationsvertrag

Für jede der vier Allocations gilt:

- eigene logische Datenbank,
- eigene `application_identity`,
- eigenes `application-password` unter `/secrets`,
- keine Rechte auf andere Allocations,
- keine gemeinsame Anwendungsrolle,
- kein gemeinsames Anwendungspasswort,
- kein gemeinsam genutztes Anwendungsschema,
- allocation-bezogener Health- und Readinessstatus,
- allocation-bezogener Backup- und Restorevertrag.

Die gemeinsame Providerinstanz bleibt eine gemeinsame Betriebs-, Ressourcen- und Fehlerdomäne. Die Daten- und Berechtigungsgrenzen der Allocations bleiben dennoch getrennt.

## Secrets-Vertrag

`/secrets` ist die einzige Secrets-Wurzel. Für den späteren Plan sind ausschließlich folgende nicht geheime Referenzen vorgesehen:

```text
/secrets/database-service/providers/postgresql-main/administrative-password
/secrets/database-service/allocations/gitea/application-password
/secrets/database-service/allocations/openbao/application-password
/secrets/database-service/allocations/semaphore/application-password
/secrets/database-service/allocations/nodered/application-password
```

Dieser Entscheidungsdurchlauf legt keine dieser Dateien an. Er dokumentiert weder Werte, Hashes, Beispielpasswörter noch Connection Strings. `/secrets` und das lokale ausgeschlossene `secrets/` bleiben unverändert.

## Begründung

- PostgreSQL 18 bildet den verbindlichen Major-Rahmen, ohne Sicherheits- und Fehlerkorrekturen späterer 18.x-Minor-Versionen auszuschließen.
- Die gemeinsame Instanz reduziert zunächst den Betriebsaufwand.
- Eine logische Datenbank und eigene Identität pro Consumer bewahren die vereinbarte Allocation-Isolation.
- Gitea, OpenBao und Semaphore UI besitzen anwendungseigene Schema-Lebenszyklen.
- Node-RED erhält einen bewusst begrenzten relationalen Anwendungsdatenspeicher.
- RALF Core wird nicht vor seiner Implementierung und seinem Migrationsvertrag vorweggenommen.

## Konsequenzen

- Der spätere Plan muss genau eine Providerinstanz und genau vier initiale Allocations beschreiben.
- Vor einer Installation wird die dann aktuelle stabile 18.x-Version ermittelt und gegen die unterstützten Consumer-Versionen geprüft.
- PostgreSQL 19 oder ein anderes Major-Upgrade darf nicht durch normale Aktualisierung eingeführt werden.
- Jede Allocation benötigt eigene Identität, Secret-Referenz, Health, Readiness, Backup und Restore.
- OpenBao und Node-RED besitzen die dokumentierten deployment-spezifischen Storage-Grenzen.
- Die konkrete technische Umsetzung bleibt vollständig offen und benötigt einen neuen Plan.

## Fortschreibung durch ADR-0006

[ADR-0006](ADR-0006-postgresql-runtime-profile.md) entscheidet die bei Annahme dieses ADR noch offenen Punkte zu Betriebssystem, Betriebsform, Paketquelle, Referenzressourcen sowie den grundsätzlichen Netzwerk-, TLS-, SCRAM-, Secret- und Backupgrenzen. Der zugehörige [read-only Deploymentplan](../operations/postgresql-main-deployment-plan.md) setzt diese Grenzen ausschließlich als Validierung und Plandarstellung um.

## Weiterhin nicht entschieden

- konkrete VMID, Storage, Bridge, Adresse, FQDN, DNS-Server und Consumer-CIDRs,
- konkretes externes Backupziel und Retention,
- Consumer-Zugriffsmodell auf die unter `/secrets` verwahrten Dateien,
- erneute Kompatibilitätsprüfung der versionierten Referenzmatrix unmittelbar vor Installation,
- konkrete logische Datenbanknamen und PostgreSQL-Benutzernamen,
- Secret-Rotation,
- zulässige Erweiterungen und Detailkonfiguration.

## Nächster Schritt

Der read-only Deploymentplan für PostgreSQL 18, eine Providerinstanz, vier isolierte logische Allocations und Secrets ausschließlich unter `/secrets` ist nun spezifiziert. Als Nächstes wird getrennt definiert, wie ein späterer Apply Mutationen, Recovery und Einzelbestätigungen sicher begrenzt. Bis dahin findet keine Mutation statt.
