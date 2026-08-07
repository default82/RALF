# ADR-0008: Host-/Gast-Implementierung der PostgreSQL-Provisionierung

- **Status:** Angenommen
- **Datum:** 2026-08-06

## Kontext

ADR-0007 bindet jede Provisionierung an einen unmittelbar neu berechneten `PLAN_READY`-Hash, trennt normalen Apply und Resume und verbietet automatischen Rollback. Der nächste Schritt benötigt real verwendbaren Code, darf aber noch keine reale Konfiguration, Secrets oder Infrastruktur verändern.

## Entscheidung

`postgresql-main` erhält einen getrennten Python-Host-/Gast-Pfad ausschließlich mit der Standardbibliothek. Planer und Deploypfad verwenden dieselbe importierte Planlogik. Mutierende Läufe halten eine exklusive Prozesssperre und schreiben Planevidenz sowie Marker atomar. Jede mehrteilige Phase besitzt persistenten Einzelteilfortschritt.

Hostcode begrenzt Proxmox-Aufrufe, sichere Hostdateien, Secret- und PKI-Erzeugung, Bundletransfer und Backupstreaming. Gastcode begrenzt Ubuntu-, PostgreSQL-, TLS-, HBA-, Rollen-, Allocation- und lokale Verifikationsschritte. Produktive Testschalter und freie Befehlsübergabe sind ausgeschlossen.

## Hash- und Freigabegrenze

Apply lädt alle Inputs und Beobachtungen unmittelbar neu, verlangt sauberen getrackten Repositoryzustand und vergleicht den bestätigten Plan-SHA-256 vor jeder Mutation. Resume besitzt einen eigenen, erneut berechneten SHA-256. Eine Abweichung blockiert ohne Mutation.

## Sperre und Marker

Die Sperre liegt auf `/run/lock/ralf-postgresql-main.lock` und verwendet nicht blockierendes `fcntl.flock`. Der Marker unter `/secrets` bindet Repository-, Plan-, Konfigurations-, Matrix- und Artefakthashes, Phase, offene Einzelmutation, geordneten Teilfortschritt, VMID, öffentliche Zertifikatfingerprints, Backupevidenz und nicht geheime Fehlerklassen.

## Secrets und PKI

Genau vier Kennwörter entstehen mit mindestens 384 Bit Entropie ausschließlich unter `/secrets`. Secretwerte erscheinen nicht in Plan, Marker, Log, argv oder normaler Umgebung. Die PKI-Policy verwendet RSA 4096/3650 Tage für die interne CA und RSA 3072/397 Tage für den TLS-Server mit SHA-256 und `serverAuth`. Der Server-SAN bindet exakt FQDN und IPv4-Adresse; der CA-Key verlässt den Host nicht.

## Provisionierungsgrenzen

Der Produktionspfad modelliert genau einen unprivilegierten Ubuntu-26.04-LXC, genau einen Start, Ubuntu-Pakete für PostgreSQL Major 18, Peer-Administration, TLS, SCRAM-SHA-256, vier isolierte logische Datenbanken mit NOLOGIN-Eigentümern und getrennten Loginrollen sowie vier allocation-bezogene Custom-Format-Backups. PGDG, PostgreSQL 19, Docker, breite HBA-Regeln, automatische Reboots, Retries und Rollbacks sind ausgeschlossen.

## Readiness-Korrektur

Die Erstprovisionierung kann ohne laufende Consumer keine positive Verbindung aus deren späteren Quellnetzen beweisen. Sie darf deshalb nur Provider-Readiness und lokal verifizierte Allocation-Konfiguration melden. `allocation_readiness` bleibt `consumer_validation_pending`, bis die jeweilige Consumerinstallation TLS/SCRAM aus einer freigegebenen Quelle bestätigt.

## Recovery

Vor jeder Einzelmutation wird das geplante Element atomar markiert; nach der Mutation wird es erst nach Verifikation bestätigt. Resume prüft bestätigte Phasen und Einzelteile read-only und setzt nur an der ersten offenen Grenze fort. Temporäre Gast-Secrets werden auch bei Fehlern bereinigt und bei einem bestätigten Resume identisch neu bereitgestellt, wenn sie für die Fortsetzung erforderlich sind. Persistente Artefakte werden weder automatisch gelöscht noch zurückgesetzt.

## Sicherheitsfolgen

- Symlinks und unsichere Metadaten blockieren sicherheitsrelevante Hostpfade.
- Kritische Dateien werden exklusiv oder atomar mit Datei- und Verzeichnis-fsync veröffentlicht.
- PostgreSQL-Geheimnisse gelangen nur über Standardinput in lokale administrative SQL-Ausführung.
- Ein Bereinigungsfehler wird zusätzlich zur ursprünglichen Fehlerklasse sichtbar.
- Backups werden vor atomarer Veröffentlichung technisch geprüft.

## Konsequenzen

- Der Code ist real verwendbar, aber noch nicht für eine reale Ausführung freigegeben.
- Fault Injection muss jede persistente Einzelgrenze abdecken.
- Ein benötigter Containerreboot bleibt ein eigener Planungs- und Freigabeschritt.
- Echte Consumer-Readiness wird erst bei der jeweiligen Consumerinstallation erreicht.

## Verworfene Alternativen

### Zweite Planung im Deployer

Verworfen, weil Plan und Ausführung sonst voneinander abweichen könnten.

### Shellskripte mit zusammengesetzten Befehlen

Verworfen, weil feste Argumentlisten, Standardinput für Secrets und injizierbare Backends klarere Sicherheitsgrenzen bieten.

### Ein ungeteilter Gastlauf

Verworfen, weil ein Crash zwischen Allocations oder Konfigurationsschritten nicht eindeutig fortsetzbar wäre.

### Consumer-Readiness lokal behaupten

Verworfen, weil ein lokaler Administrationsnachweis keine reale Verbindung aus dem vorgesehenen Consumer-Netz ersetzt.

### Automatischer Rollback

Verworfen gemäß ADR-0007, weil er Secrets, PKI, Datenbanken oder Backupevidenz zerstören könnte.

## Nicht ausgeführt

Es wurden kein realer Proxmox-Plan, Apply oder Resume-Apply ausgeführt. `/secrets`, LXC, PostgreSQL, Netzwerke und Consumer blieben unverändert.

## Nächster Schritt

Die reale Deploymentkonfiguration wird kontrolliert unter `/secrets` angelegt und anschließend ausschließlich read-only geplant. Erst ein separat geprüfter und ausdrücklich bestätigter `PLAN_READY`-Hash darf die erste reale Mutation freigeben.
