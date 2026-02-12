# Repository Migration - GitHub → Gitea

**Datum:** 2026-02-12
**Von:** https://github.com/default82/RALF.git
**Nach:** http://10.10.20.12:3000/RALF-Homelab/ralf.git

## Änderungen:
- Git Remote "origin" zeigt jetzt auf Gitea (RALF-Homelab/ralf)
- GitHub-Remote umbenannt zu "github-backup" (read-only)
- Alle Commits und Historie migriert

## Zugriff:
- **Gitea Web-UI:** http://10.10.20.12:3000/RALF-Homelab/ralf
- **Git Clone:** http://10.10.20.12:3000/RALF-Homelab/ralf.git
- **SSH Clone:** ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git

## Nächste Schritte:
- [ ] Semaphore Git-Remote auf Gitea umstellen
- [ ] SSH-Keys für passwortlosen Zugriff einrichten
- [ ] GitHub-Repo auf read-only setzen

