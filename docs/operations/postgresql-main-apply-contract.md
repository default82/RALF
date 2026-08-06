# Apply-Vertrag für `postgresql-main`

## Status und Geltungsbereich

Dieses Dokument spezifiziert den streng begrenzten Apply für die PostgreSQL-Providerinstanz `postgresql-main` mit exakt den Allocations `gitea`, `openbao`, `semaphore` und `nodered`.

Der Vertrag ist durch einen getrennten Host-/Gast-Pfad implementiert und ausschließlich lokal mit Fakes und temporären Dateisystemen geprüft. Der bestehende Planer bleibt read-only. Dieses Dokument autorisiert noch keine reale Infrastrukturmutation und keine Ausführung gegen das echte `/secrets` oder Proxmox.

## Plan ist die einzige Zielquelle

Der [read-only Deploymentplaner](postgresql-main-deployment-plan.md) ist die einzige Quelle des fachlichen und technischen Zielplans. Ein späterer Apply darf keine zweite Planung erzeugen, fehlende Werte ergänzen oder eine abweichende Mutationsliste ableiten.

```text
Konfiguration unter /secrets
          │
          ▼
Read-only Plan
          │
          ├── kanonische Planrepräsentation
          ├── Plan-SHA-256
          ├── PLAN_READY oder PLAN_BLOCKED
          └── vollständige Mutationsliste
          │
          ▼
ausdrückliche Nutzerfreigabe für genau diesen Hash
          │
          ▼
Apply-Preflight berechnet denselben Plan erneut
          │
          ├── gleicher Hash → Apply zulässig
          └── anderer Hash → APPLY_BLOCKED_PLAN_CHANGED
```

Ein Plan mit Warnungen kann freigabefähig sein. Sobald mindestens ein Blocker besteht, lautet der Zustand `PLAN_BLOCKED`; eine Bestätigung ist dann technisch unwirksam.

## Maschinenlesbarer Plan und Hash

Der Planer unterstützt Text und kanonisch serialisierbares JSON:

```bash
sudo python3 scripts/postgresql-main-plan.py \
  plan \
  --config /secrets/database-service/providers/postgresql-main/deployment.toml \
  --format json
```

Die JSON-Repräsentation enthält unter anderem Repository-Commit, SHA-256 der nicht geheimen Deploymentkonfiguration und Versionsmatrix, aufgelöste Proxmox-Beobachtungen, vollständige Planinputs, reine Secretmetadaten, Backupbeobachtungen, Warnungen, Blocker, ausgeschlossenen Umfang und die geordnete Mutationsliste.

Der Plan-Hash wird aus kanonischem UTF-8-JSON mit sortierten Objektschlüsseln und ohne Formatierungsleerraum berechnet. `generated_at` und `plan_sha256` selbst sind ausgeschlossen. Warnungen und Blocker werden vor dem Hashen dedupliziert und sortiert; ihre zufällige Diagnose-Reihenfolge ändert den Hash nicht.

Gebunden werden mindestens:

- Repository-Commit,
- Konfigurations- und Versionsmatrixhash,
- VMID, Storage, freie Kapazität, Bridge und Template,
- Betriebssystem, Architektur, unprivilegierter Zustand, nesting und Ressourcen,
- Provideradresse, FQDN, Gateway und DNS,
- alle vier Allocations, Datenbanknamen, Anwendungsidentitäten und CIDR-Allowlists,
- ausschließlich Pfad, Existenz, Typ, Eigentümer, Gruppe, Modus und Sicherheitsstatus von Secretreferenzen,
- Backupziel, Kapazität und Schutzbestätigung,
- geplante Mutationen, ausgeschlossener Umfang, sicherheitsrelevante Warnungen und sämtliche Blocker.

Nicht gebunden oder ausgegeben werden Secretwerte, Inhalts-Hashes von Secrets, Passwortlängen, private Schlüssel, vollständige Umgebungsvariablen oder rein darstellende Textabschnitte.

## Spätere Freigabegrenze

Der implementierte, noch nicht real ausgeführte Aufruf lautet:

```bash
sudo python3 scripts/postgresql-main-deploy.py \
  apply \
  --config /secrets/database-service/providers/postgresql-main/deployment.toml \
  --confirm-plan-sha256 <64-HEX-ZEICHEN>
```

Unmittelbar vor der ersten Mutation muss Apply:

1. die reale Konfiguration erneut und symlinksicher laden,
2. die versionierte Matrix erneut laden,
3. sämtliche erlaubten read-only Proxmox-Prüfungen wiederholen,
4. Secret- und Backupmetadaten erneut erheben,
5. den vollständigen Plan erneut erzeugen,
6. `PLAN_READY` verlangen,
7. den Plan-SHA-256 neu berechnen,
8. exakt mit `--confirm-plan-sha256` vergleichen.

Jede Abweichung ergibt `APPLY_BLOCKED_PLAN_CHANGED`, bevor eine Datei, ein Secret, ein Container oder anderer Zustand verändert wird. Eine Eingabe wie `Continue? [y/N]` ist keine zulässige Freigabe. Die ausdrückliche menschliche Freigabe im Nutzerkontext bleibt zusätzlich erforderlich; der Hashparameter bindet diese Freigabe technisch an genau einen geprüften Zustand.

## Normaler Apply-Preflight

Ein normaler Apply ist ausschließlich zulässig, wenn gleichzeitig:

- kein Provisionierungsmarker existiert,
- weder Ziel-VMID noch Zielhostname belegt sind,
- keine Ziel-Secrets und keine Ziel-PKI existieren,
- keine vorgesehenen initialen Backupzieldateien existieren,
- Planstatus `PLAN_READY` ist,
- der bestätigte Hash exakt übereinstimmt.

Vorhandene Teilzustände werden nicht adoptiert. Sie sperren den normalen Apply und verlangen den gesonderten Resume-Vertrag oder eine eigene manuelle Recovery-Entscheidung.

## Provisionierungsmarker

Der spätere Marker liegt ausschließlich hier:

```text
/secrets/database-service/providers/postgresql-main/provisioning-state.json
```

Er ist `root:root`, Modus `0600`, kein Symlink und wird bei jeder Phasenänderung atomar ersetzt. Er enthält mindestens:

| Feld | Bedeutung |
| --- | --- |
| `schema_version` | Version des Markervertrags. |
| `operation_id` | Eindeutige, nicht geheime Referenz des Provisionierungsvorgangs. |
| `provider_instance_id` | Muss exakt `postgresql-main` sein. |
| `plan_sha256` | Freigegebener und unmittelbar vor Apply neu berechneter Plan. |
| `configuration_sha256` | Gebundene Deploymentkonfiguration. |
| `version_matrix_sha256` | Gebundene Versionsmatrix. |
| `phase` | Letzte sicher bestätigte Zustandsphase. |
| `completed_phases` | Geordnete Liste vollständig verifizierter Phasen. |
| `created_at`, `updated_at` | UTC-Zeitstempel mit Zeitzoneninformation. |
| `vmid` | Gebundene Ziel-VMID. |
| `artifact_hashes` | Hashes ausschließlich nicht geheimer Skripte, Konfigurationen, Manifeste und öffentlicher Zertifikate. |
| `last_error` | Nicht geheime Fehlerklasse und Kurzdiagnose. |

Der Marker enthält niemals Secretwerte, Kennworthashes, private Schlüssel oder Connection Strings. `completed_phases` wird erst nach der phasenspezifischen Verifikation erweitert.

## Stabile Zustandsmaschine

| Position | Markerphase nach Erfolg | Mutation | Verifikation vor Fortschritt |
| --- | --- | --- | --- |
| 1 | `planned` | vorhandene Konfigurations- und Marker-Eltern revalidieren, Planbindung und Marker | Hash, Markerinhalt und Metadaten stimmen. |
| 2 | `secret_directories_ready` | Marker-Eltern revalidieren und übrige erlaubte `/secrets`-Verzeichnisse ergänzen | Jeder Pfad ist echtes `root:root`-Verzeichnis `0700`. |
| 3 | `secrets_ready` | vier Anwendungskennwörter | Genau vier reguläre, nicht leere Dateien `root:root` `0600`; keine Ausgabe. |
| 4 | `pki_ready` | dedizierte Provider-PKI | Schlüssel und Zertifikate besitzen richtige Metadaten; SAN bindet FQDN und IP. |
| 5 | `lxc_created` | genau ein `pct create` | Gestoppter LXC entspricht vollständig dem Plan. |
| 6 | `lxc_started` | genau ein `pct start` | Container und Basisbetrieb sind gesund. |
| 7 | `guest_bundle_ready` | temporäres Gastbundle | Manifest und Metadaten stimmen; Secrets liegen nur geschützt unter `/run`. |
| 8 | `guest_os_ready` | Ubuntu vorbereiten | Paketstatus, Release, Architektur, Netzwerk und Units sind geprüft. |
| 9 | `postgresql_installed` | PostgreSQL 18 installieren | Paket, Major-Version und genau ein erwarteter Cluster sind nachgewiesen. |
| 10 | `postgresql_configured` | TLS-, SCRAM-, Peer- und HBA-Konfiguration | Effektive Konfiguration besitzt keine breite oder schwache Regel. |
| 11 | `allocations_created` | vier Datenbanken und getrennte Identitäten | Exakte Objekte und minimale Attribute sind nachgewiesen. |
| 12 | `readiness_verified` | Providerzustand und lokale Allocation-Konfiguration prüfen | Provider ist ready; Konfiguration und Isolation sind verifiziert, Consumer-Konnektivität bleibt ausstehend. |
| 13 | `backups_verified` | vier initiale Backups | Archive existieren geschützt, sind neu und technisch geprüft. |
| 14 | `completed` | Marker abschließen und temporäre Secrets bereinigen | Keine Gastlaufzeit-Secrets; alle Abschlussprüfungen weiterhin grün. |

Ein späterer Implementierungsplan darf diese Reihenfolge nicht stillschweigend ändern. Zusätzliche Unterprüfungen benötigen weiterhin eine eindeutige Zuordnung zu genau einer Phase.

## Phase 1: Apply-Zustand vorbereiten

Die reale Deploymentkonfiguration liegt vor dem Apply bereits unter `/secrets/database-service/providers/postgresql-main/deployment.toml`. Daher müssen die vier Marker-Eltern `/secrets`, `/secrets/database-service`, `/secrets/database-service/providers` und `/secrets/database-service/providers/postgresql-main` schon als symlinkfreie `root:root`-Verzeichnisse `0700` existieren. Phase 1 validiert sie ausschließlich read-only und legt weder einen fehlenden Elternpfad noch die Konfiguration an.

Danach sind ausschließlich der vollständige erneute read-only Preflight, der exakte Hashvergleich, die atomare Neuanlage des Provisionierungsmarkers und das Speichern des kanonischen Plans sowie nicht geheimer Artefakthashes als Evidenz erlaubt.

Vor Übergang zu `planned` wird geprüft:

- Marker war zuvor nicht vorhanden,
- Plan ist `PLAN_READY`,
- bestätigter und neu berechneter Hash stimmen überein,
- jeder vorhandene Marker-Elternpfad ist ein echtes `root:root`-Verzeichnis `0700`,
- gespeicherte Evidenz reproduziert dieselben Hashes,
- Marker ist regulär, `root:root`, `0600` und enthält keine unerlaubten Felder.

## Phase 2: Secrets-Verzeichnisse vorbereiten

Später dürfen exakt folgende Verzeichnisse angelegt werden:

```text
/secrets
/secrets/database-service
/secrets/database-service/providers
/secrets/database-service/providers/postgresql-main
/secrets/database-service/providers/postgresql-main/pki
/secrets/database-service/allocations
/secrets/database-service/allocations/gitea
/secrets/database-service/allocations/openbao
/secrets/database-service/allocations/semaphore
/secrets/database-service/allocations/nodered
```

Die vier vorhandenen Marker-Eltern werden erneut read-only validiert. Phase 2 darf ausschließlich das PKI-Verzeichnis, den Allocation-Stamm und die vier Allocation-Verzeichnisse ergänzen. Jeder Pfad ist `root:root` und `0700`. Symlinks, Traversierung, Auflösung außerhalb `/secrets` sowie gruppen- oder weltzugängliche Komponenten sind Konflikte. Vor `secret_directories_ready` werden alle Komponenten erneut per Metadaten geprüft.

## Phase 3: Anwendungskennwörter erzeugen

Später dürfen genau vier Secretdateien exklusiv und atomar neu entstehen:

```text
/secrets/database-service/allocations/gitea/application-password
/secrets/database-service/allocations/openbao/application-password
/secrets/database-service/allocations/semaphore/application-password
/secrets/database-service/allocations/nodered/application-password
```

Sie sind kryptographisch zufällig, ausreichend entropiereich, nicht leer, `root:root` und `0600`. Werte erscheinen niemals in Standardausgabe, Logs, Prozessargumenten oder normalen Umgebungsvariablen. Vorhandene Dateien werden nicht überschrieben.

Nur ein gültiger Resume darf bereits vorhandene, erwartete, sicher geschützte Secrets wiederverwenden. Unerwartete oder unsichere Dateien ergeben `RESUME_CONFLICT`. Es wird kein dauerhaftes Remote-Superuserkennwort erzeugt; lokale Administration verwendet Unix-Socket, Peer-Authentifizierung und das lokale `postgres`-Systemkonto.

## Phase 4: Provider-PKI erzeugen

Vorgesehene Hostpfade:

```text
/secrets/database-service/providers/postgresql-main/pki/ca.key
/secrets/database-service/providers/postgresql-main/pki/ca.crt
/secrets/database-service/providers/postgresql-main/pki/server.key
/secrets/database-service/providers/postgresql-main/pki/server.crt
```

Die interne CA gilt ausschließlich für diesen Provider. Ihr privater Schlüssel verbleibt auf dem Proxmox-Host. Das Serverzertifikat bindet den bestätigten FQDN und die bestätigte Provider-IP. Private Schlüssel sind `root:root` `0600`; öffentliche Zertifikate sind höchstens `0644`.

Es gibt keine automatische System-Trust-Installation, öffentliche ACME-Anfrage oder OPNsense-Änderung. Die versionierte [PKI-Policy](../../deploy/postgresql/pki-policy.toml) legt RSA 4096 und 3650 Tage für die CA sowie RSA 3072 und 397 Tage für das Serverzertifikat fest. Vor `pki_ready` werden Metadaten, Zertifikatskette, SAN und Übereinstimmung von Server-Key und Serverzertifikat geprüft, ohne private Inhalte zu protokollieren.

## Phase 5: LXC anlegen

Später ist genau ein `pct create` erlaubt. Zielvertrag:

- Hostname `postgresql-main`,
- Ubuntu 26.04 LTS, amd64,
- `unprivileged: 1`,
- ausschließlich `nesting=1`,
- statische Adresse, Bridge, Gateway und DNS aus dem bestätigten Plan,
- CPU, RAM, Swap, Root-Disk und Storage aus dem Plan,
- keine Mountpoints und keine GPU.

Der Container bleibt unmittelbar nach Erstellung gestoppt. Es gibt keinen automatischen zweiten Create-Versuch. Vor `lxc_created` müssen VMID, Hostname, Status, Ressourcen, Disk, Bridge, IP, Gateway, DNS, Unprivilegiertheit und Featuremenge exakt stimmen.

## Phase 6: LXC starten

Später ist genau ein `pct start` erlaubt. Ein fehlgeschlagener Start wird nicht automatisch wiederholt.

Vor `lxc_started` sind read-only nachzuweisen:

- Container `running`,
- systemd betriebsfähig und keine fehlgeschlagene Unit,
- richtiger Hostname, Ubuntu-Version und Architektur,
- geplante Adresse, Route und DNS-Konfiguration,
- HTTPS-Zugriff ausschließlich zu den benötigten Ubuntu-Paketquellen,
- ausreichender freier Speicher.

## Phase 7: Temporäres Provisionierungsbundle

Das spätere Bundle liegt ausschließlich unter `/run/ralf-database-provision/`, `root:root`, `0700`. Es enthält ausschließlich:

- versioniertes Gast-Provisionierungsskript,
- nicht geheime Providerkonfiguration,
- Manifest,
- Serverzertifikat und Server-Key,
- öffentliches CA-Zertifikat,
- vier temporäre Kopien der Anwendungskennwörter.

Temporäre Secretdateien sind `0600`. Vor `guest_bundle_ready` müssen Manifest, Artefakthashes, Dateimenge, Eigentümer und Modi stimmen. Keine geheime Datei darf außerhalb dieses flüchtigen Bereichs liegen.

Alle temporären Secretkopien werden bei Erfolg und Fehler entfernt. Diese Sicherheitsbereinigung ist kein Rollback. Kein Secret darf nach `/etc`, `/var/lib`, `/opt`, `/root` oder `/home` kopiert werden; einzige Ausnahme ist der kontrolliert installierte PostgreSQL-Server-Key im späteren TLS-Betriebspfad.

## Phase 8: Ubuntu vorbereiten

Erlaubt sind später:

- Paketmanagerzustand prüfen,
- Paketlisten aus offiziellen Ubuntu-26.04-Quellen aktualisieren,
- vorhandene Ubuntu-Pakete kontrolliert aktualisieren,
- PostgreSQL-Paketkandidat prüfen,
- ausschließlich Major 18 akzeptieren,
- erforderliche Basis- und PostgreSQL-Pakete installieren.

Nicht erlaubt sind PGDG, PostgreSQL 19, ein Release-Upgrade oder automatischer Containerneustart. Erfordert der Zielzustand einen Neustart, wird mit `PROVISIONING_PAUSED_REBOOT_REQUIRED` angehalten. Ein Neustart benötigt einen getrennten Plan, eine neue Freigabe und danach einen Resume-Plan.

Paketdienststarts müssen so kontrolliert sein, dass PostgreSQL vor der Sicherheitskonfiguration nicht remote lauscht. Die konkrete, zu testende Technik wird erst im Implementierungs-PR entschieden. Vor `guest_os_ready` werden Release, Architektur, Paketmanagerintegrität, Netzwerk, freier Speicher und Unitstatus geprüft.

## Phase 9: PostgreSQL-Installation verifizieren

Vor `postgresql_installed` müssen exakt PostgreSQL Major 18, der erwartete Paketumfang und genau ein erwarteter Cluster bestätigt sein. Es darf kein PostgreSQL-19-Paket, kein zusätzlicher Cluster und keine PGDG-Quelle vorhanden sein. Der Dienst darf zu diesem Zeitpunkt höchstens über lokale sichere Standardgrenzen erreichbar sein.

Bei Paketfehlern gibt es weder automatischen Retry noch Deinstallation oder Clusterlöschung.

## Phase 10: PostgreSQL konfigurieren

Zielzustand:

- Major 18 und genau ein erwarteter Cluster,
- `listen_addresses` ist die bestätigte Provider-IP, niemals `0.0.0.0`,
- TLS aktiv,
- Kennwortverschlüsselung und Remote-Authentifizierung ausschließlich SCRAM-SHA-256,
- keine Remote-Superuseranmeldung,
- lokale Administration ausschließlich per Peer,
- allocation-spezifische `hostssl`-Regeln für jeweilige Datenbank, Identität und bestätigte CIDR-Allowlist.

Unzulässig sind globale Regeln wie `host all all 0.0.0.0/0`, allgemeines `hostssl all all`, Remote-`trust`, `md5`, `password` oder Consumer-übergreifende Freigaben.

Vor `postgresql_configured` werden die effektiv geladenen Einstellungen, Listener, TLS-Kette und vollständige HBA-Regelmenge geprüft. Konfigurationsdateien und Server-Key müssen sichere Metadaten besitzen.

## Phase 11: Allocations anlegen

Später werden exakt `gitea`, `openbao`, `semaphore` und `nodered` angelegt. Jede Allocation erhält:

- genau eine logische Datenbank,
- einen abgeleiteten NOLOGIN-Eigentümer,
- eine getrennte Login-Anwendungsidentität,
- das eigene bereits vorhandene Kennwort,
- keine Superuser-, `CREATEDB`-, `CREATEROLE`- oder Replikationsrechte,
- keine Rechte auf fremde Datenbanken.

Die Anwendung darf ausschließlich in ihrer logischen Datenbank eigene Schemaobjekte erzeugen und migrieren, aber die Datenbank nicht löschen. Die exakte PostgreSQL-Rechteabbildung wird erst im Apply-Implementierungs-PR festgelegt und mit positiven sowie negativen Tests belegt.

Vor `allocations_created` müssen Objektmenge, Eigentum, Loginstatus, Rollenattribute und fehlende Fremdrechte vollständig bestätigt sein. Ein vorhandener unerwarteter Zustand wird nicht korrigiert oder gelöscht, sondern als Konflikt gemeldet.

## Phase 12: Providerzustand und lokale Allocation-Konfiguration prüfen

Für jede Allocation sind lokal administrativ nachzuweisen:

- Datenbank, Eigentümer, Login- und NOLOGIN-Rollen besitzen exakt die vorgesehenen Attribute,
- der gespeicherte Passwortverifier verwendet SCRAM-SHA-256, ohne ihn auszugeben,
- `SET ROLE` sowie Lese- und Schreibtest in der eigenen Datenbank sind erfolgreich; das Testobjekt wird unmittelbar entfernt,
- keine Anwendungsidentität besitzt `CONNECT` auf eine fremde Allocation,
- `CREATEDB`, `CREATEROLE`, Superuser- und Replikationsrechte abgelehnt,
- HBA und Serverkonfiguration erlauben ausschließlich TLS/SCRAM aus den geplanten Allowlists.

Kennwörter werden bei der Anlage nur aus geschützten temporären Passwortdateien gelesen. Eine echte TLS-/SCRAM-Anmeldung aus einem Consumer-Netz gehört ausdrücklich nicht zu dieser lokalen Prüfung.

Providerweit werden aktiver Dienst, Major-Version, TLS, SCRAM, Listener ausschließlich auf der Provider-IP, Unix-Socket, lokale Peer-Administration, sichere Daten- und Konfigurationsmetadaten sowie das Fehlen fehlgeschlagener Units geprüft.

Ohne laufende Consumer ist kein positiver Verbindungsnachweis aus deren späteren Quellnetzen möglich. Nach erfolgreicher Phase gilt deshalb ausschließlich:

```text
provider_status = ready
allocation_configuration = verified
consumer_connectivity = pending
allocation_readiness = consumer_validation_pending
```

Die spätere Consumerinstallation muss TLS/SCRAM aus einer ausdrücklich erlaubten Quelle positiv nachweisen, bevor eine Allocation als `ready` bezeichnet werden darf.

## Phase 13: Initiale Backups

Für jede der vier Allocations entsteht später genau ein neues logisches PostgreSQL-Custom-Format-Backup unter:

```text
<backup.host_root>/postgresql-main/<allocation-id>/
```

Das Backup wird zum Proxmox-Host gestreamt; es verbleibt keine dauerhafte Kopie im LXC. Jede Zieldatei ist neu, `root:root`, `0600`, besitzt Zeitstempel und nicht geheime Metadaten und überschreibt niemals eine vorhandene Datei. Der Archiveinhalt wird technisch geprüft. Eine erzeugte Datei ohne erfolgreiche Prüfung ist kein Backup.

Es gibt keine automatische Retention und keinen Backup-Retry. Nur vier erfolgreich geprüfte Archive erlauben `backups_verified`.

## Phase 14: Abschluss

Erst wenn alle vorherigen Phasen erneut konsistent sind:

- wird der Marker atomar auf `completed` gesetzt,
- wird das temporäre Gastbundle entfernt,
- wird nachgewiesen, dass unter `/run` keine temporären Secretkopien verbleiben,
- wird ein nicht geheimer Abschlussstatus dokumentiert.

Der Marker bleibt als historische Provisionierungsevidenz erhalten. Er darf nicht als Secretablage oder Erlaubnis für spätere Wartungsmutationen verwendet werden.

## Fehlervertrag

Bei jedem Fehler werden später mindestens berichtet:

- `operation_id` und `plan_sha256`,
- aktuelle und abgeschlossene Phasen,
- letzte Mutation,
- VMID und Containerstatus,
- PostgreSQL-Paket-, Dienst- und Clusterstatus,
- vorhandene Allocations,
- Secret- und PKI-Metadaten,
- temporäre Gastartefakte,
- Backupstatus,
- nächster zulässiger Schritt.

Secretwerte bleiben ausgeschlossen. Es gibt keinen automatischen zweiten Versuch, Resume, Reboot, Paket-Retry, Datenbank-Neuanlageversuch, Backup-Retry oder Rollback.

Der Provisionierungsweg besitzt keinen automatischen Rollback. Jeder persistente Teilerfolg bleibt bis zu einer gesonderten Recovery-Entscheidung erhalten.

## Sicherheitsbereinigung ist kein Rollback

Auch bei Fehlern müssen temporäre Secretkopien und Passwortdateien unter `/run` entfernt, offene Dateideskriptoren geschlossen, ausschließlich vom aktuellen Vorgang gestartete temporäre Hilfsprozesse beendet und noch nicht veröffentlichte temporäre Dateien entfernt werden.

Nicht als Bereinigung zulässig sind das Löschen einer Datenbank, Identität, eines LXC, Host-Secrets, der PKI oder eines Backups sowie eine PostgreSQL-Deinstallation. Solche Rücknahmen sind destruktive Recovery und benötigen einen eigenen Plan mit eigener Freigabe.

## Resume und Recovery

Normaler Apply und Resume bleiben getrennte Befehls- und Freigabegrenzen. Die vollständige Zustands- und Recovery-Matrix steht in [PostgreSQL Provisioning Recovery](../recovery/postgresql-main-provisioning-recovery.md).

## Implementierungsstand

Host-/Gast-Pfad, atomarer Marker mit Einzelteilfortschritt, exklusive Sperre, Secret- und PKI-Erzeugung, LXC-Befehlsbau, Gastphasen, allocation-bezogene Backups und hashgebundener Resume sind implementiert. [Implementierungsdetails und lokale Prüfgrenzen](postgresql-main-apply-implementation.md) sind separat dokumentiert. Noch wurden weder reale Deploymentkonfiguration noch reale Infrastruktur verändert.
