# Database-Allocation-Lebenszyklus

## Status und Zweck

Dieses Dokument präzisiert die Zustände und fachlichen Operationen einer [Database Allocation](../contracts/database-allocation-v0.1.md). Es beschreibt weder eine technische API noch SQL, ausführbare Befehle oder automatische Übergänge.

Providerinstanz und Allocation besitzen getrennte Lebenszyklen. Eine Providerinstanz kann `ready` sein, während eine einzelne Allocation beispielsweise `migration_required`, `suspended` oder `failed` ist.

## Zustände

Lese- und Schreibangaben beziehen sich auf den normalen Consumerzugriff. Administrative Aktionen sind ausschließlich geplante, ausdrücklich freigegebene Lebenszyklusoperationen.

| Zustand | Bedeutung | Lesen | Schreiben | Administrative Aktionen |
| --- | --- | --- | --- | --- |
| `requested` | Consumerbedarf ist beschrieben; eine Providerinstanz ist noch nicht ausgewählt. | nein | nein | Anforderungen prüfen und Allocation planen |
| `planned` | Providerinstanz, Isolation, Identitäten und Secret-Referenzen sind geplant; keine Mutation ist erfolgt. | nein | nein | Plan prüfen und Bereitstellung freigeben |
| `provisioning` | Logische Datenbank und technische Identitäten werden kontrolliert angelegt. | nein | nein | nur freigegebene Bereitstellung und Verifikation |
| `configured` | Datenbank und Identitäten existieren; Schema und Readiness sind noch nicht zwingend bestätigt. | nur gezielte Prüfung | nein | Verifikation oder Migrationsplanung |
| `migration_required` | Datenbank ist erreichbar, der benötigte Schemastand fehlt. | nur wenn Vertrag und Schema dies sicher erlauben | nein | Migration planen |
| `migrating` | Eine freigegebene Migration läuft. | nur gemäß Migrationsplan | nein, außer ausdrücklich erforderliche Migrationsschritte | Migration überwachen und verifizieren |
| `ready` | Provider, Datenbank, Identitäten, Fähigkeiten, Schema und minimale Rechte sind bestätigt. | ja | ja | kontrollierte Betriebsoperationen |
| `degraded` | Allocation ist eingeschränkt; Grund und erlaubte Zugriffe sind sichtbar. | abhängig von Einschränkung | abhängig von Einschränkung | Diagnose und gesondert freigegebene Korrektur |
| `backup_running` | Allocation-bezogenes Backup läuft. | grundsätzlich ja, sofern Backupplan nichts anderes verlangt | nur wenn Konsistenzvertrag es erlaubt | Backup überwachen und verifizieren |
| `restore_planned` | Restorequelle, Ziel und Auswirkungen sind geprüft und warten auf eigene Freigabe. | nach aktuellem Zustand | nach aktuellem Zustand | Restoreplan prüfen oder verwerfen |
| `restore_running` | Freigegebener Restore betrifft genau diese Allocation. | nein | nein | Restore überwachen und abschließend prüfen |
| `suspended` | Allocation bleibt vorhanden; normaler Anwendungszugriff ist bewusst deaktiviert. | nein | nein | Diagnose, Backup oder geplantes Resume |
| `deleting` | Ausdrückliche Löschung ist vorbereitet oder aktiv; Backup und Retention sind berücksichtigt. | nein | nein | nur freigegebene Löschung und Nachprüfung |
| `deleted` | Aktive Allocation ist entfernt; Backups können bis zum Retentionsende fortbestehen. | nein | nein | ausschließlich Retention und Abschlussnachweis |
| `failed` | Sicherer Allocation-Betrieb ist nicht möglich. | nein | nein | Diagnose und gesondert geplante Wiederherstellung |

Ein Start des Database Service oder eines Consumers löst keinen mutierenden Zustandsübergang aus.

## Übergangsregeln

- `requested` wird erst nach vollständiger und bestätigter Planung zu `planned`.
- `planned` wird nur durch eine freigegebene Bereitstellung zu `provisioning`.
- `configured` wird erst nach vollständiger Verifikation zu `ready` oder bei fehlendem Schemastand zu `migration_required`.
- `migration_required` wird ausschließlich durch eine eigene Freigabe zu `migrating`.
- `migrating`, `backup_running` und `restore_running` werden nie allein aufgrund eines gestarteten Prozesses als erfolgreich abgeschlossen gemeldet.
- `suspended` bleibt bestehen, bis ein ausdrückliches Resume geplant, freigegeben und verifiziert wurde.
- `deleting` verlangt eine vorherige Betrachtung von Retention und vorhandenen Backups.
- `deleted` bedeutet nicht, dass Sicherungen außerhalb ihrer Aufbewahrungsregeln verschwunden sind.
- Ein unbekannter oder widersprüchlicher Zustand wird nicht als `ready` interpretiert.

## Fachliche Allocation-Operationen

Die Namen gliedern den Vertrag und sind keine Funktionssignaturen:

- `plan_allocation`
- `create_allocation`
- `verify_allocation`
- `plan_migration`
- `apply_migration`
- `suspend_allocation`
- `resume_allocation`
- `plan_backup`
- `create_backup`
- `verify_backup`
- `plan_restore`
- `restore_backup`
- `rotate_allocation_secrets`
- `plan_delete_allocation`
- `delete_allocation`

Jede mutierende Operation benötigt später:

1. aktuellen Zustand,
2. Zielzustand,
3. Voraussetzungen,
4. sichtbare Mutationen,
5. Risiken,
6. ausdrückliche Freigabe,
7. anschließende Verifikation.

Eine Freigabe für einen Plan gilt nicht automatisch für einen anderen Plan oder eine andere Allocation.

## Allocation-Plan

Ein späterer Plan zeigt mindestens:

- Consumer und Consumer-Profil,
- Providerinstanz und Provider-Version,
- Isolationsklasse,
- nicht geheime logische Datenbankreferenz,
- Schema-Lebenszyklus,
- erforderliche und optionale Fähigkeiten,
- vorgesehene technische Identitäten,
- nicht geheime Secret-Referenzen unter `/secrets`,
- Netzwerkgrenze,
- Backup- und Restore-Policy,
- Ressourcenanforderungen,
- geplante Mutationen,
- Validierungsschritte,
- Grenzen eines Rollbacks.

Der Plan enthält keine Secretwerte, Kennworthashes, Zugangsdaten oder ausführbaren freien Befehle.

## Health und Readiness

### Allocation-Health

Health beantwortet, ob die zugewiesene Datenbank und ihre Identitäten grundsätzlich existieren und technisch erreichbar sind. Health allein erlaubt keinen normalen Consumerzugriff.

### Allocation-Readiness

Readiness beantwortet, ob genau dieser Consumer seine Allocation sicher verwenden kann. Mindestens erforderlich sind:

- Providerinstanz `ready`,
- logische Datenbank vorhanden,
- Verbindung mit der vorgesehenen Anwendungsidentität möglich,
- keine Rechte auf fremde Allocations,
- erforderliche Fähigkeiten vorhanden,
- Schema kompatibel,
- keine blockierende Migration,
- kein Restore aktiv,
- Secret-Referenzen gültig,
- Speicherzustand ausreichend.

Eine Providerinstanz kann bereit sein, obwohl eine einzelne Allocation nicht bereit ist. Umgekehrt wird eine Allocation bei nicht bereitem Provider nicht als bereit gemeldet.

## Backup-Lebenszyklus

| Zustand | Bedeutung |
| --- | --- |
| `planned` | Umfang, Allocation, Ziel, Konsistenz- und Verifikationsanforderung sind beschrieben. |
| `running` | Freigegebene Erzeugung läuft. |
| `created` | Backupobjekt wurde erzeugt, ist aber noch nicht technisch verifiziert. |
| `verified` | Integrität und vereinbarte Metadaten sind geprüft; erst jetzt ist das Backup verwendbar. |
| `failed` | Erzeugung oder Verifikation ist fehlgeschlagen. |
| `expired` | Aufbewahrungsfrist ist abgelaufen; weitere Behandlung folgt der Retention-Policy. |

Der Referenzstandard für 0.1 ist ein logisches Backup genau einer Allocation. Providerweite physische Sicherungen sind eine spätere Zusatzfähigkeit.

## Restore-Lebenszyklus

| Zustand | Bedeutung |
| --- | --- |
| `planned` | Verifiziertes Backup, Ziel-Allocation und Auswirkungen sind benannt. |
| `validated` | Quelle, Ziel, Kompatibilität und Zielzustand wurden geprüft; Ausführung bleibt unfreigegeben. |
| `running` | Der ausdrücklich freigegebene Restore läuft. |
| `completed` | Restore sowie Integritäts- und Readiness-Prüfung sind erfolgreich. |
| `failed` | Restore oder Abschlussprüfung ist fehlgeschlagen. |

Ein Restore betrifft ausschließlich die bezeichnete Allocation. Die Auswahl einer Allocation autorisiert niemals eine providerweite Wiederherstellung oder eine Änderung fremder Allocations.

## Secret-Rotation

`rotate_allocation_secrets` ist eine eigene geplante Operation. Sie darf bestehende Werte nicht automatisch überschreiben, muss Consumerumschaltung und Verifikation sichtbar machen und darf Secretwerte weder im Plan noch in Logs offenlegen. Die konkrete Rotationsfolge bleibt offen.

## Providerneutrale Fehlerklassen

- `provider_not_ready`
- `provider_version_incompatible`
- `allocation_conflict`
- `allocation_not_found`
- `allocation_not_ready`
- `allocation_already_exists`
- `identity_conflict`
- `secret_reference_invalid`
- `secret_already_exists`
- `secret_unavailable`
- `capability_missing`
- `schema_lifecycle_conflict`
- `migration_required`
- `migration_failed`
- `backup_failed`
- `backup_not_verified`
- `restore_conflict`
- `restore_failed`
- `isolation_violation`
- `resource_exhausted`

PostgreSQL-spezifische SQLSTATE-Werte bleiben intern im Provideradapter. Sie werden nicht Bestandteil des providerneutralen Allocation-Vertrags.

## Offene Entscheidungen

- zulässige Übergangsmatrix für anwendungseigene Migrationen,
- Verhalten bei teilweise erfolgreicher Bereitstellung,
- sicherer Rotationsablauf für laufende Consumer,
- konkrete Ressourcen- und Netzwerkgrenzen,
- Retention und Speicherort logischer Backups,
- Kriterien für einen eingeschränkten Lesezugriff in `degraded` oder `maintenance`,
- Nachweis fehlender Rechte auf fremde Allocations,
- Grenzen und Verfahren eines späteren Rollbacks.

**Nächster Schritt:** Der [read-only Deploymentplan](../operations/postgresql-main-deployment-plan.md) bildet das in ADR-0005 und ADR-0006 gewählte Profil ohne Mutation ab. Danach wird ein getrennter Apply-Vertrag spezifiziert; noch keine Allocation wird angelegt oder verändert.
