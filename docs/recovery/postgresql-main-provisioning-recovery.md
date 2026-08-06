# Recovery-Vertrag für die Provisionierung von `postgresql-main`

## Zweck und Grenze

Dieses Dokument definiert, wie ein zukünftig unterbrochener Provisionierungsvorgang eindeutig erkannt, ausschließlich read-only bewertet und nach eigener Freigabe fortgesetzt werden darf. Es implementiert weder Resume noch Recovery und autorisiert keine Infrastrukturänderung.

Der Grundsatz lautet:

> Es gibt keinen automatischen Rollback. Ein unterbrochener Zustand wird bewahrt, vollständig geprüft und nur durch einen gesondert geplanten sowie hashgebunden bestätigten Resume fortgesetzt.

## Erkennung eines unterbrochenen Zustands

Primäre Evidenz ist der atomare Marker:

```text
/secrets/database-service/providers/postgresql-main/provisioning-state.json
```

Ein Vorgang gilt als unterbrochen, wenn ein valider Marker mit einer Phase ungleich `completed` existiert oder wenn Markerphase und tatsächlicher read-only Zustand voneinander abweichen. Zusätzlich werden ausschließlich Metadaten und Status geprüft:

- gebundener ursprünglicher Plan-, Konfigurations- und Matrixhash,
- geordnete `completed_phases`,
- Ziel-VMID und Containerkonfiguration,
- vorhandene Secret- und PKI-Pfade samt sicheren Metadaten,
- Paket-, Cluster-, Dienst- und Allocation-Zustände,
- temporäre Gastartefakte,
- vorhandene initiale Backups.

Ein Marker ist nur gültig, wenn Schema, Provider-ID, Operation-ID, Hashformate, VMID, Phasenreihenfolge, Artefakthashes, Eigentümer `root:root`, Modus `0600` und Symlinkfreiheit stimmen. Unbekannte Phasen, übersprungene Phasen, widersprüchliche Hashes oder unerlaubte Felder ergeben `RESUME_CONFLICT`.

Ein Teilzustand ohne gültigen Marker wird niemals adoptiert. Er benötigt eine manuelle Recovery-Entscheidung.

## Normaler Apply und Resume

Ein normaler Apply ist bei vorhandenem Marker oder irgendeinem Zielartefakt gesperrt. Der implementierte read-only Resume-Aufruf lautet:

```bash
sudo python3 scripts/postgresql-main-deploy.py \
  resume-plan \
  --config /secrets/database-service/providers/postgresql-main/deployment.toml
```

Der implementierte, noch nicht real ausgeführte mutierende Resume-Aufruf lautet:

```bash
sudo python3 scripts/postgresql-main-deploy.py \
  resume-apply \
  --config /secrets/database-service/providers/postgresql-main/deployment.toml \
  --confirm-resume-sha256 <64-HEX-ZEICHEN>
```

Der Resume-Plan bindet mindestens ursprünglichen `plan_sha256`, Markerhash, aktuelle read-only Beobachtungen, letzte bestätigte Phase, bereits abgeschlossene Mutationen, nächste zulässige Mutation sowie bestehende Konflikte. `--confirm-resume-sha256` bestätigt exakt diesen Resume-Plan und nicht pauschal den ursprünglichen Apply.

Ein Resume darf:

- nur einen vollständig validen Marker verwenden,
- jede abgeschlossene Phase read-only erneut verifizieren,
- ausschließlich mit der ersten nicht abgeschlossenen Phase fortfahren,
- keine bestätigte Mutation wiederholen,
- keine Secrets oder PKI neu erzeugen,
- keinen Container erneut erstellen oder automatisch neu starten,
- keine vorhandene Datenbank oder Identität neu anlegen,
- keine Backupdatei überschreiben.

Jede Abweichung zwischen Marker und Wirklichkeit ergibt `RESUME_CONFLICT`, bevor eine Mutation erfolgt.

## Recovery-Matrix

| Letzte bestätigte Phase | Erkennbare Evidenz | Nächster zulässiger Resume-Schritt | Niemals automatisch |
| --- | --- | --- | --- |
| vor `planned` | kein Marker und keine Zielartefakte | neuen read-only Plan erzeugen; normaler Apply kann nach neuer Hashfreigabe beginnen | Teilzustände adoptieren oder löschen |
| `planned` | gültiger Marker, gebundene Planevidenz und sichere Marker-Elternpfade | Phase 2: Eltern revalidieren und ausschließlich fehlende PKI- sowie Allocation-Verzeichnisse anlegen | Marker überschreiben, Plan wechseln, Eltern neu anlegen oder Infrastruktur ohne Revalidierung verändern |
| `secret_directories_ready` | erlaubte Verzeichnisse vollständig `root:root` `0700`, keine Secretdateien | Phase 3: genau vier Secrets exklusiv erzeugen | Verzeichnisse löschen oder fremde Pfade übernehmen |
| `secrets_ready` | vier erwartete, sichere, nicht leere Anwendungskennwörter | Phase 4: PKI mit denselben Secretartefakten erzeugen | Secrets löschen, neu erzeugen, überschreiben oder rotieren |
| `pki_ready` | sichere PKI-Metadaten, gültige Kette und passende SANs, kein LXC | Phase 5: exakt geplanten LXC gestoppt anlegen | PKI löschen, neu aufbauen oder durch andere Zertifikate ersetzen |
| `lxc_created` | exakt konfigurierter, gestoppter LXC | Phase 6: nach Revalidierung genau einmal starten | `pct create` wiederholen, LXC zerstören oder Parameter still ändern |
| `lxc_started` | exakt konfigurierter LXC läuft; Gastbasis geprüft | Phase 7: geprüftes temporäres Bundle übertragen | automatischer Stop, Neustart, Reboot oder Destroy |
| `guest_bundle_ready` | Bundlemanifest stimmt; temporäre Dateien besitzen sichere Metadaten | Phase 8: Ubuntu vorbereiten oder zuvor verbliebene temporäre Secrets bereinigen und Bundle identisch neu bereitstellen | andere Artefakte übernehmen oder Secretwerte neu erzeugen |
| `guest_os_ready` | Ubuntu-Zustand und Paketmanager sind geprüft; kein ungeklärter Rebootbedarf | Phase 9: PostgreSQL-18-Installation verifizieren beziehungsweise abschließen | Release-Upgrade, PGDG, PostgreSQL 19 oder automatischer Reboot |
| `postgresql_installed` | Major 18 und genau ein erwarteter Cluster; Remotezugriff noch nicht breit | Phase 10: geplante Sicherheitskonfiguration einspielen | Pakete deinstallieren, Cluster löschen oder Installationsversuch blind wiederholen |
| `postgresql_configured` | effektive Peer-, TLS-, SCRAM-, Listener- und HBA-Grenzen stimmen | Phase 11: exakt vier Allocations anlegen | Konfiguration zurücksetzen oder breite Übergangsregel aktivieren |
| `allocations_created` | vier Datenbanken, NOLOGIN-Eigentümer und getrennte Login-Identitäten stimmen | Phase 12: vollständige positive und negative Isolationstests ausführen | Datenbanken, Rollen oder Secrets löschen beziehungsweise neu anlegen |
| `readiness_verified` | Provider ready; lokale Allocation-Konfiguration und Isolation verifiziert; Consumer-Konnektivität ausstehend | Phase 13: vier neue, eindeutige Backups erzeugen und prüfen | Consumer-Readiness vor echtem Quellnetz-Nachweis behaupten oder fremde/alte Backups bestätigen |
| `backups_verified` | vier neue geprüfte Archive mit sicheren Metadaten | Phase 14: Abschluss erneut prüfen, temporäre Secrets entfernen, Marker abschließen | Backups entfernen, überschreiben oder unvalidiert ersetzen |
| `completed` | Abschlussmarker, keine temporären Gastsecrets, gesamter Zielzustand konsistent | keine Provisionierungsmutation; nur read-only Status oder eigener Wartungsplan | Provisionierung erneut starten oder Marker als allgemeine Wartungsfreigabe verwenden |

## Pausierter Neustartbedarf

Wenn Phase 8 einen Containerneustart verlangt, bleibt die letzte vollständig bestätigte Phase erhalten und `last_error` wird auf `PROVISIONING_PAUSED_REBOOT_REQUIRED` gesetzt. Es erfolgt kein automatischer Neustart und kein weiterer Provisionierungsschritt.

Ein separater read-only Neustartplan muss Anlass, aktuellen Containerzustand, geplanten einen Neustart und anschließende Prüfungen darstellen. Erst nach eigener Hashfreigabe darf der Neustart erfolgen. Danach wird ein neuer Resume-Plan erzeugt; der vorherige Resume-Hash ist verbraucht.

## Phasenspezifische Grenzen

### Secrets vorhanden, noch kein LXC

Secrets bleiben erhalten und dürfen nur vom passenden Resume verwendet werden. Automatische Löschung oder Rotation ist verboten. Ein Abbruch vor PKI oder LXC rechtfertigt keine Rücknahme der bereits erzeugten Vertrauensanker.

### PKI vorhanden, noch kein LXC

CA und Serverartefakte bleiben erhalten. Resume prüft Kette, SAN, Key-Zuordnung und Metadaten. Es erzeugt weder eine zweite CA noch ein neues Serverzertifikat.

### LXC vorhanden

Der Container wird nicht automatisch zerstört, gestoppt, gestartet oder umkonfiguriert. Resume prüft VMID, Hostname, Ressourcen, Storage, Netzwerk, Unprivilegiertheit und Featuremenge. Bereits die kleinste nicht erklärte Abweichung blockiert.

### Pakete oder Cluster vorhanden

Es gibt keine Paketdeinstallation, keinen zweiten blinden Installationsversuch und keine automatische Clusterlöschung. Der Resume-Plan unterscheidet installierte Pakete, Clusterzustand, Dienststatus und effektive Netzwerkgrenze, bevor eine nächste Phase freigabefähig wird.

### Allocations vorhanden

Datenbanken, Eigentümer, Login-Identitäten und Secretzuordnung werden vollständig verglichen. Es gibt keine automatische Löschung, Neuerstellung, Kennwortrotation oder Privilegienerweiterung. Unerwartete Objekte oder Rechte sind Konflikte.

### Backups vorhanden

Geprüfte Backups bleiben unverändert. Dateiname, Pfad, Metadaten und technischer Prüfnachweis werden verglichen. Ein Resume erzeugt nur noch fehlende, eindeutig neue Archive und überschreibt niemals einen vorhandenen Namen.

## Sicherheitsbereinigung nach Fehlern

Sicherheitsbereinigung ist unabhängig von fachlicher Recovery und darf auch nach einem Fehler ausgeführt werden:

| Erlaubt oder verpflichtend | Grenze |
| --- | --- |
| temporäre Secretkopien unter `/run/ralf-database-provision/` entfernen | nur flüchtige Kopien, niemals Host-Secrets oder installierten Server-Key |
| temporäre Passwortdateien entfernen | nur vom aktuellen Vorgang erzeugte Laufzeitkopien |
| offene Dateideskriptoren schließen | keine Änderung persistenter Artefakte |
| temporäre Hilfsprozesse beenden | ausschließlich vom aktuellen Vorgang gestartet |
| noch nicht atomar veröffentlichte temporäre Dateien entfernen | veröffentlichte Marker, Secrets, PKI oder Backups bleiben erhalten |

Nicht zulässig sind Datenbank- oder Rollenlöschung, LXC-Destroy, Host-Secret- oder PKI-Löschung, Backup-Löschung, PostgreSQL-Deinstallation oder Rücksetzen einer bestätigten Konfiguration.

## Fehlerbericht

Jeder Abbruch hält ohne Geheimnisse fest:

- Operation und ursprünglichen Plan-Hash,
- Markerphase und abgeschlossene Phasen,
- letzte versuchte Mutation,
- festgestellte Abweichung,
- VMID, Container-, Paket-, Cluster- und Dienststatus,
- vorhandene Allocation-IDs,
- Secret-, PKI-, Bundle- und Backupmetadaten,
- ausgeführte Sicherheitsbereinigung,
- genau den nächsten zulässigen read-only Planungsschritt.

Es gibt keinen automatischen zweiten Versuch, Resume, Neustart, Paket-, Datenbank- oder Backup-Retry.

## Manuelle Recovery-Entscheidungen

Folgende Handlungen benötigen immer einen neuen, eigenen destruktiven oder rotierenden Plan:

- Host-Secrets löschen oder rotieren,
- CA oder Serverzertifikat ersetzen,
- LXC stoppen, neu starten, zerstören oder ersetzen,
- PostgreSQL-Pakete deinstallieren oder Cluster entfernen,
- Datenbanken oder Identitäten löschen,
- bestehende Backups löschen,
- Marker wegen nachgewiesener Beschädigung archivieren oder ersetzen.

Der künftige Provisionierungscode darf keine dieser Entscheidungen aus einem Fehlerzustand ableiten.

## Implementierungsstand

Resume-Plan und Resume-Apply validieren Marker, gespeicherten Originalplan, Artefakthashes, abgeschlossene Phasen und Einzelteilfortschritte. Fault-Injection-Tests decken jede persistente Grenze ab. Der Pfad wurde ausschließlich lokal mit Fakes ausgeführt; für einen realen Einsatz fehlen weiterhin die kontrolliert angelegte Deploymentkonfiguration, der reale read-only Plan und dessen neue ausdrückliche Freigabe.
