# Implementierung des `postgresql-main`-Apply-/Resume-Pfads

## Status und Grenze

Der Host-/Gast-Pfad setzt den [Apply-Vertrag](postgresql-main-apply-contract.md) und die [Recovery-Matrix](../recovery/postgresql-main-provisioning-recovery.md) technisch um. Er wurde ausschließlich mit lokalen Fakes, Fault Injection, temporären Dateisystemen und einer lokalen OpenSSL-Prüfung getestet. In diesem Meilenstein wurden weder ein realer Plan noch `apply` oder `resume-apply` gegen Proxmox ausgeführt; das echte `/secrets` blieb unverändert.

## Gemeinsame Planquelle

`scripts/postgresql-main-plan.py` bleibt eine eigenständige read-only CLI. `scripts/postgresql-main-deploy.py` importiert dieselbe Planfunktion direkt und parst keine formatierte Ausgabe. Unmittelbar vor Apply werden Konfiguration, Versionsmatrix, Git-Commit, sauberer getrackter Repositoryzustand, Proxmox-Beobachtungen, Secretmetadaten und Backupziel erneut geprüft. Ausschließlich `PLAN_READY` plus exakte Übereinstimmung mit `--confirm-plan-sha256` öffnet die Mutationsgrenze.

Die Host-CLI enthält nur:

```text
apply
resume-plan
resume-apply
```

Es gibt kein `--force`, `--yes`, Überspringen von Prüfungen, Reset, Rollback oder produktives Testbackend.

## Exklusive Ausführung und sichere Dateien

Mutierende Läufe halten für ihre gesamte Dauer eine nicht blockierende `fcntl.flock`-Sperre auf `/run/lock/ralf-postgresql-main.lock`. Marker und kanonische Planevidenz liegen unter `/secrets/database-service/providers/postgresql-main/`, sind `root:root` `0600` und werden mit symlinksicheren, fsync-gestützten Dateifunktionen veröffentlicht.

Die zentralen Dateifunktionen verwenden nach Möglichkeit `dir_fd`, `O_NOFOLLOW`, `O_EXCL` und `O_CLOEXEC`. Sicherheitsrelevante Veröffentlichungen fsyncen Datei und Elternverzeichnis. Unsichere vorhandene Metadaten werden nicht repariert, sondern blockieren.

## Marker und Einzelteilfortschritt

Der Marker bindet Operation, Repository-Commit, Plan-, Konfigurations-, Matrix- und Skripthashes, VMID, abgeschlossene Phasen, offene Einzelmutation, öffentliche Zertifikatfingerprints, Backupevidenz und nicht geheime Fehlerklassen. Secretwerte, Secret-Inhaltshashes, private Schlüssel und Connection Strings sind ausgeschlossen.

Mehrteilige Phasen führen geordneten Fortschritt für:

- sechs erlaubte Secretverzeichnisse,
- vier Anwendungskennwörter,
- zehn Gastbundle-Artefakte,
- Ubuntu-Update und -Validierung,
- Paketinstallation und -Validierung,
- TLS, PostgreSQL-Einstellungen, HBA, Start und Validierung,
- vier Allocations,
- Provider plus vier lokale Allocation-Prüfungen,
- vier Backups.

Vor jeder persistenten Einzelmutation wird `in_progress_phase` samt Element atomar gespeichert. Erst nach erfolgreicher Verifikation wird das Element bestätigt. Ein Fehlerbericht lädt stets den neuesten persistenten Marker; er kann keinen neueren Fortschritt mit einem älteren In-Memory-Zustand überschreiben.

## Secrets und PKI

Genau vier ASCII-Anwendungskennwörter mit mindestens 384 Bit Zufallsentropie entstehen exklusiv unter `/secrets/database-service/allocations/<id>/application-password`, `root:root` `0600`. Sie werden weder ausgegeben noch gehasht und gelangen nicht in Argumente oder normale Umgebungsvariablen. SQL mit einem Kennwort wird ausschließlich im Speicher erzeugt und über Standardinput an lokales `psql` übergeben.

Die versionierte [PKI-Policy](../../deploy/postgresql/pki-policy.toml) verwendet:

- CA: RSA 4096, SHA-256, 3650 Tage, kritische CA- und Key-Usage-Grenzen,
- Server: RSA 3072, SHA-256, 397 Tage, `serverAuth`, exakt FQDN und IPv4-Adresse als SAN.

OpenSSL wird nur mit festen Argumentlisten aufgerufen. CA-Key und Server-Key bleiben `0600`; nur der Server-Key gelangt kontrolliert in das PostgreSQL-TLS-Verzeichnis. Der Marker speichert ausschließlich SHA-256-Fingerprints der öffentlichen Zertifikate.

## Host- und Gasttrennung

Der Host besitzt eine kleine Backendgrenze für feste read-only und mutierende Proxmox-Aufrufe, Bundletransfer, Gastphasen und Backupstreams. Tests injizieren ein lokales Fake-Backend direkt; die produktive CLI besitzt dafür keinen Schalter.

Der Host baut genau einen begrenzten `pct create` für den bestätigten unprivilegierten Ubuntu-26.04-LXC mit ausschließlich `nesting=1` und genau einen `pct start`. Nach jedem Schritt wird die geplante Konfiguration beziehungsweise der Status geprüft. Es gibt keinen automatischen zweiten Versuch, Stop, Reboot oder Destroy.

Das Gastprogramm akzeptiert ausschließlich `classify`, eine fest benannte `apply-phase`, interne Phasenverifikation und Sicherheitsbereinigung. Es akzeptiert weder freie Befehle noch freie Phasennamen.

## Ubuntu und PostgreSQL

Die Gastbasis verlangt UID 0, Ubuntu 26.04 und amd64/x86_64. Sie lehnt Paketmanagerkonflikte und PGDG-Quellen ab, führt kontrolliertes Ubuntu-Update und Full-Upgrade aus und pausiert bei `/var/run/reboot-required` mit `PROVISIONING_PAUSED_REBOOT_REQUIRED`. Es erfolgt kein automatischer Reboot.

Die Installation akzeptiert ausschließlich Ubuntu-Pakete `postgresql-18` und `postgresql-client-18`. Eine temporäre, konfliktprüfende `policy-rc.d` verhindert unkontrollierten Paketdienststart. Danach muss genau der gestoppte Cluster `18/main` existieren; PostgreSQL 19, weitere Major-Versionen oder zusätzliche Cluster sind Konflikte.

Vor dem Start werden TLS, `listen_addresses` auf die bestätigte Provider-IP, `scram-sha-256`, TLS mindestens 1.2 und eine vollständig deterministische HBA installiert. HBA erlaubt lokale Peer-Administration für `postgres`, lehnt sonstige lokale Zugriffe ab und enthält pro Allocation nur eigene Datenbank, Loginidentität, begrenzte IPv4-CIDRs, `hostssl` und SCRAM. Breite Netze, `hostssl all all`, Remote-`trust`, `md5` und Klartextkennwortauthentifizierung sind ausgeschlossen.

## Allocations und Readiness

Für `gitea`, `openbao`, `semaphore` und `nodered` entstehen jeweils:

- eine eigene UTF-8-Datenbank,
- eine abgeleitete NOLOGIN-Eigentümerrolle `<application_identity>_owner`,
- eine getrennte LOGIN-Anwendungsrolle ohne Superuser-, CREATEDB-, CREATEROLE- oder Replikationsrecht,
- Mitgliedschaft ausschließlich in der eigenen Eigentümerrolle,
- entzogenes globales `PUBLIC CONNECT` und keine Fremddatenbankrechte.

Lokale administrative Prüfungen bestätigen Rollenattribute, Eigentum, SET-ROLE-Schreib-/Lesetest, HBA, TLS, SCRAM und fehlende Fremdrechte. Ohne laufende Consumer kann jedoch keine Verbindung aus deren späteren Quellnetzen bestätigt werden. Der Marker meldet daher:

```text
provider_status = ready
allocation_configuration = verified
consumer_connectivity = pending
allocation_readiness = consumer_validation_pending
```

## Backups, Resume und Fehler

Jede Allocation wird als PostgreSQL-Custom-Format direkt vom Gast in eine exklusive temporäre Hostdatei gestreamt. Nach fsync und erfolgreichem `pg_restore --list` wird sie atomar veröffentlicht. Der Marker bindet Pfad, Größe und SHA-256; Inhalte werden nicht ausgegeben. Ein Resume überspringt nur exakt passende bestätigte Archive und überschreibt keinen Namen.

`resume-plan` prüft Marker, Originalplan, Repository- und Skripthashes sowie alle abgeschlossenen Phasen read-only und bindet die exakt nächste Mutation an `resume_sha256`. `resume-apply` berechnet diesen Zustand erneut. Bestätigte Einzelmutationen werden nicht wiederholt. Nach Fehlerbereinigung dürfen ausschließlich fehlende flüchtige Gast-Secretkopien identisch wieder bereitgestellt werden.

Es gibt keinen automatischen Rollback und keinen automatischen Retry. Persistente Secrets, PKI, LXC, Pakete, Datenbanken, Rollen und Backups bleiben erhalten. Sicherheitsbereinigung entfernt nur temporäre Secretkopien, unveröffentlichte temporäre Dateien und eigene Hilfsressourcen. Ein Bereinigungsfehler wird zusätzlich gemeldet und verdeckt nicht die ursprüngliche Fehlerklasse.

## Nächster Schritt

Nach Review und Merge wird die reale Deploymentkonfiguration kontrolliert unter `/secrets` angelegt. Danach folgt genau ein realer read-only Plan. Erst nach Prüfung von Hash, Netzwerk, Ressourcen, Backupziel und Blockern darf ein einzelner Apply erneut ausdrücklich freigegeben werden.
