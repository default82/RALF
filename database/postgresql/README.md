# PostgreSQL DB Struktur

## Konventionen

- DB Name: `ralf_db`
- DB User: `ralf_user`
- Erweiterungen/Migrationen unter `database/postgresql/migrations/`

## Migrations-Lauf (Beispiel)

```bash
psql -h 10.10.20.10 -U ralf_user -d ralf_db -f database/postgresql/migrations/0001_create_ralf_status_events.sql
```
