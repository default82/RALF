# ADR-0007: Apply- und Recovery-Grenzen für `postgresql-main`

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

ADR-0005 wählt PostgreSQL 18, `postgresql-main` und vier Allocations. ADR-0006 legt das unprivilegierte Ubuntu-26.04-LXC-Laufzeitprofil und seine Netzwerk-, TLS-, SCRAM-, Secret- und Backupgrenzen fest. Der vorhandene Planer erhebt den Zielzustand ausschließlich read-only.

Vor einer späteren Umsetzung muss ausgeschlossen sein, dass ein Apply auf veraltete Beobachtungen, eine veränderte Konfiguration oder eine abweichende eigene Planung reagiert. Außerdem muss ein Teilerfolg erhalten und nachvollziehbar bleiben, ohne Datenbanken, Secrets, Zertifikate oder Backups durch vermeintlich hilfreichen Rollback zu zerstören.

## Entscheidung

Ein zukünftiger PostgreSQL-Apply wird an den SHA-256 eines unmittelbar zuvor neu berechneten `PLAN_READY`-Plans gebunden. Mutationen erfolgen in einer festen Reihenfolge mit atomarem Provisionierungsmarker und phasenspezifischer Verifikation. Es gibt keinen automatischen Rollback. Ein unterbrochener Zustand darf ausschließlich durch einen gesondert geplanten und hashgebunden bestätigten Resume fortgesetzt werden.

Diese Entscheidung implementiert keinen Apply oder Resume und verändert keine Infrastruktur.

## Planbindung

Der read-only Planer bleibt einzige Quelle des Zielplans. Seine kanonische JSON-Repräsentation bindet mindestens:

- Repository-Commit,
- Konfigurations- und Versionsmatrixhash,
- aufgelöste Proxmox-Ziele und Ressourcen,
- Netzwerk, FQDN und Allowlists,
- genau vier Allocations mit Datenbanknamen und Anwendungsidentitäten,
- ausschließlich Metadaten der Secret- und PKI-Pfade,
- Backupziel und Schutzstatus,
- Mutationen, Blocker und sicherheitsrelevante Warnungen.

`generated_at` und darstellende Texte werden nicht gehasht. Die Reihenfolge gleichwertiger Diagnosen beeinflusst den Hash nicht. Secretwerte, Secret-Inhaltshashes und private Schlüssel sind weder Planinhalt noch Hashinput.

## Freigabegrenze

Ein späterer Apply verlangt einen expliziten 64-stelligen Hashparameter. Unmittelbar vor der ersten Mutation lädt er alle Inputs neu, wiederholt alle read-only Prüfungen und berechnet den Plan neu.

Nur `PLAN_READY` plus exakte Hashgleichheit ist freigabefähig. Eine Warnung kann bestehen bleiben; ein einziger Blocker sperrt. Eine Abweichung ergibt `APPLY_BLOCKED_PLAN_CHANGED` ohne Mutation.

Die technische Hashbestätigung ergänzt die ausdrückliche Nutzerfreigabe, ersetzt sie aber nicht. Eine ungebundene interaktive Ja/Nein-Abfrage ist ausgeschlossen.

## Mutationsphasen

Die stabile Reihenfolge lautet:

1. `planned`: Plan neu prüfen, ausschließlich sichere Marker-Elternpfade anlegen, Hash binden und Marker anlegen.
2. `secret_directories_ready`: Marker-Eltern revalidieren und ausschließlich PKI- sowie Allocation-Verzeichnisse ergänzen.
3. `secrets_ready`: genau vier Anwendungskennwörter exklusiv erzeugen.
4. `pki_ready`: dedizierte interne Provider-PKI erzeugen.
5. `lxc_created`: genau einen unprivilegierten, gestoppten LXC anlegen.
6. `lxc_started`: LXC genau einmal starten und prüfen.
7. `guest_bundle_ready`: geschütztes temporäres Bundle unter `/run` übertragen.
8. `guest_os_ready`: Ubuntu kontrolliert vorbereiten; bei Rebootbedarf pausieren.
9. `postgresql_installed`: ausschließlich PostgreSQL Major 18 installieren und prüfen.
10. `postgresql_configured`: Peer, TLS, SCRAM, Listener und HBA begrenzen.
11. `allocations_created`: vier logische Datenbanken mit getrennten Eigentümern und Login-Identitäten anlegen.
12. `readiness_verified`: Provider- und Allocation-Isolation positiv und negativ prüfen.
13. `backups_verified`: vier initiale logische Backups erzeugen und technisch prüfen.
14. `completed`: Abschlussmarker schreiben und temporäre Gastgeheimnisse bereinigen.

Jede Phase wird erst nach ihrer vollständigen read-only Verifikation atomar als abgeschlossen markiert. Die [vollständige Mutations- und Prüfliste](../operations/postgresql-main-apply-contract.md) ist normativ.

## Provisionierungsmarker

Der Marker liegt unter `/secrets/database-service/providers/postgresql-main/provisioning-state.json`, ist `root:root`, `0600`, symlinkfrei und enthält ausschließlich nicht geheime Identitäten, Hashes, Phasen, Zeitstempel, VMID, Artefakthashes und Fehlerstatus.

Da dieser Marker ohne Elternpfade nicht crashfest angelegt werden kann, darf Phase 1 ausschließlich `/secrets`, `database-service`, `providers` und `postgresql-main` als sichere `root:root`-Verzeichnisse `0700` vorbereiten. Phase 2 revalidiert sie und ergänzt erst dann PKI- und Allocation-Verzeichnisse. Diese explizite Ausnahme verhindert einen unmarkierten Secret- oder Infrastruktur-Teilerfolg.

Er darf keine Secretwerte, Kennworthashes, privaten Schlüssel oder Connection Strings enthalten. Er wird bei jeder bestätigten Phasenänderung atomar ersetzt und bleibt nach `completed` als historische Provisionierungsevidenz erhalten.

## Secrets-Vertrag

Persistente Secret- und PKI-Erzeugung ist ausschließlich unter `/secrets` erlaubt. Es entstehen genau vier allocation-eigene Anwendungskennwörter; kein dauerhaftes Remote-Superuserkennwort wird erzeugt. Vorhandene Dateien werden niemals automatisch überschrieben.

Die interne CA verbleibt auf dem Proxmox-Host. Das Serverzertifikat bindet den bestätigten FQDN und die Provider-IP. Laufzeiten und Rotation werden in einer späteren versionierten PKI-Policy entschieden.

Temporäre Gastkopien dürfen ausschließlich geschützt unter `/run/ralf-database-provision/` liegen und müssen bei Erfolg sowie Fehler entfernt werden. Diese Sicherheitsbereinigung ist kein Rollback. Der notwendige installierte Server-Key ist die einzige vorgesehene persistente Gastkopie eines privaten Schlüssels.

## Recovery-Grenzen

Normaler Apply setzt einen vollständig leeren Zielzustand ohne Marker voraus. Jeder Teilzustand sperrt ihn.

Ein Resume:

- validiert Marker, Hashbindung und alle abgeschlossenen Phasen,
- erzeugt einen eigenen kanonischen Resume-Plan,
- verlangt eine eigene Hashbestätigung,
- fährt ausschließlich mit der ersten offenen Phase fort,
- wiederholt keine abgeschlossene Mutation,
- löscht oder überschreibt keine vorhandenen Secrets, PKI, Container, Datenbanken, Identitäten oder Backups.

Widerspruch zwischen Marker und realem Zustand ergibt `RESUME_CONFLICT`. Ein Neustartbedarf ergibt `PROVISIONING_PAUSED_REBOOT_REQUIRED` und benötigt einen eigenen Neustartplan. Die normative [Recovery-Matrix](../recovery/postgresql-main-provisioning-recovery.md) definiert jede Teilphase.

## Kein automatischer Rollback

Automatischer Rollback ist ausgeschlossen, weil die sichere Rücknahme phasenabhängig ist und sonst Vertrauensanker, Datenbanken, Identitäten oder nachgewiesene Backups zerstören könnte.

Nicht automatisch erfolgen insbesondere:

- Secret- oder PKI-Löschung und -Rotation,
- LXC-Stop, -Reboot oder -Destroy,
- Paketdeinstallation oder Clusterlöschung,
- Datenbank- oder Rollenlöschung,
- Backup-Löschung oder Überschreiben.

Temporäre Secretkopien, unveröffentlichte temporäre Dateien, offene Deskriptoren und ausschließlich vom Vorgang gestartete Hilfsprozesse werden sicher bereinigt. Das ändert keinen bestätigten persistenten Zustand.

## Begründung

- Ein kanonischer Hash verbindet menschliche Review und technischen Preflight mit exakt demselben Zustand.
- Erneute read-only Erhebung verhindert Apply auf veralteten Planwerten.
- Ein atomarer Marker macht Teilerfolge und die nächste zulässige Phase nachvollziehbar.
- Getrennte Resume-Freigabe verhindert stille Fortsetzung nach einem Fehler oder Zeitablauf.
- Erhalt statt Rollback schützt unwiederbringliche Secrets, PKI, Datenbanken und Backupevidenz.
- Phasenspezifische Verifikation verhindert, dass eine ausgeführte Mutation fälschlich als erfolgreicher Zielzustand gilt.

## Konsequenzen

- Der Planer erhält Text- und JSON-Ausgabe sowie einen deterministischen Plan-SHA-256, bleibt aber vollständig read-only.
- Ein späterer Apply muss exakt die dokumentierte Reihenfolge und Mutationsallowlist implementieren.
- Jeder Apply- und Resume-Hash ist nur für den unmittelbar neu erhobenen Zustand relevant.
- Warnungen bleiben sichtbar; Blocker sind technisch nicht überstimmbar.
- Recovery benötigt zusätzliche Planung statt automatischer Rücknahme.
- Der Marker unter `/secrets` wird selbst Teil der externen Vertrauens- und Recovery-Grenze.

## Verworfene Alternativen

### Ungebundene interaktive Bestätigung

Verworfen, weil ein einfaches Ja nicht nachweist, welchen konkreten Plan der Nutzer gesehen hat.

### Apply erzeugt seinen eigenen Zielplan

Verworfen, weil Planer und Executor sonst unbemerkt unterschiedliche Defaults, Mutationen oder Providerentscheidungen verwenden könnten.

### Hash einer formatierten Textausgabe

Verworfen, weil rein darstellende Änderungen eine neue Freigabe erzwingen und semantische Normalisierung fehlen würde.

### Automatischer Rollback bei jedem Fehler

Verworfen, weil phasenabhängig Datenbanken, Secrets, PKI oder Backups verloren gehen könnten.

### Normaler Apply adoptiert Teilzustände

Verworfen, weil Herkunft, Vollständigkeit und vorherige Freigabe nicht sicher nachweisbar wären.

### Resume ohne neue Bestätigung

Verworfen, weil Zeitablauf und Teilerfolg den tatsächlichen Zustand gegenüber dem ursprünglichen Plan verändern.

## Offene Punkte

- konkrete Implementierung des atomaren Markers,
- Passwortentropie und sichere Generierungstechnik,
- versionierte PKI-Laufzeiten und Rotationspolitik,
- kontrollierte Paketdienststarttechnik während Installation,
- exakte PostgreSQL-Rechteabbildung für NOLOGIN-Eigentümer und Login-Anwendungen,
- technisches Schema des Resume-Plans und seiner Hashbindung,
- Gestaltung eines getrennten, ausdrücklich freizugebenden Rebootpfads,
- spätere Wartungs-, Rotations- und Deprovisionierungsverträge.

## Nächster Schritt

Nach Review und Merge kann ein weiterer lokaler Meilenstein die Marker-, Apply- und Resume-Logik ausschließlich mit Mocks und ohne reale Infrastrukturmutation entwerfen. Vor jeder echten Mutation bleiben ein vollständiger read-only Plan und eine neue ausdrückliche Hashfreigabe erforderlich.
