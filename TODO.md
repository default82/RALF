# TODO – RALF MVP

## Phase 0 – Governance

- [ ] `docs/CHARTA.md` (v1.2), `docs/ZIELBILD.md` (v1.3), `docs/BETRIEBSVERFASSUNG.md` (v1.2) als kanonischen Stand bestaetigen
- [ ] Entscheidungsweg, Gate-Regeln und DNS-Standard (`internal-zone`, Ziel: OPNsense Unbound) als operativen Standard festschreiben

## Phase 1 – Foundation Core

- [ ] MinIO bereitstellen und State-/Artefaktpfad verifizieren
- [ ] PostgreSQL bereitstellen und Basiszugriff prüfen
- [ ] Gitea bereitstellen und als kanonisches Remote etablieren
- [ ] Semaphore bereitstellen und Initial-Templates seeden
- [ ] Foundation Core End-to-End validieren

## Phase 2 – Foundation Services

- [ ] Vaultwarden bereitstellen
- [ ] Prometheus bereitstellen
- [ ] Foundation-Smokes vollständig durchführen

## Phase 3 – Erweiterung

- [ ] n8n bereitstellen
- [ ] KI-Instanz bereitstellen
- [ ] Matrix bereitstellen
- [ ] Erweiterungs-Smokes durchführen

## Phase 4 – Betriebsreife

- [ ] Semaphore-first Betrieb als Standard festlegen
- [ ] regelmäßige Drift-/Health-Checks etablieren
- [ ] jede Änderung mit Gate-Status und Nachweis abschließen
