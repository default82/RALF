# TODO – RALF Umsetzungsplan

## Phase 0 – Governance einfrieren

- [ ] Charta, Zielbild und Betriebsverfassung als Version 1.1 bestätigen
- [ ] Änderungsprozess für kanonische Dokumente verbindlich festlegen

## Phase 1 – Foundation bootstrap (verbindliche Reihenfolge)

- [ ] MinIO bereitstellen und Bucket-Policy definieren
- [ ] PostgreSQL bereitstellen und Grundschema verifizieren
- [ ] Gitea bereitstellen und als kanonisches Remote etablieren
- [ ] Semaphore bereitstellen und Initial-Templates seeden
- [ ] Foundation-End-to-End-Smoketest durchführen

## Phase 2 – Sicherheitsbasis

- [ ] Secret-Handling ohne Klartext im Repo durchsetzen
- [ ] Least-Privilege-Prinzip auf Dienste und Runner anwenden
- [ ] Incident-Modus und Eskalationspfad dokumentiert testen

## Phase 3 – Erweiterungswellen

- [ ] Vaultwarden integrieren
- [ ] Prometheus integrieren
- [ ] n8n integrieren
- [ ] KI-Instanz integrieren

## Phase 4 – Betriebsreife

- [ ] Regelmäßige Drift-/Health-Checks etablieren
- [ ] Verifizierungs- und Rollback-Pfade je Dienst dokumentieren
- [ ] Jede Änderung mit Gate-Status und Artefaktnachweis abschließen
