# Semaphore SSH Keys Setup

## Status

✅ SSH-Key-Pair generiert: `ralf-ansible`
✅ Public Key zu allen Containern hinzugefügt
✅ SSH-Zugriff getestet und funktionsfähig
⏳ Private Key muss zu Semaphore Key Store hinzugefügt werden

## SSH-Key Locations

**Private Key:**
```
/root/.ssh/semaphore/ralf-ansible
```

**Public Key:**
```
/root/.ssh/semaphore/ralf-ansible.pub
```

## Getestete Container

| Container | Hostname | IP | SSH-Zugriff |
|-----------|----------|-----|-------------|
| CT 2010 | svc-postgres | 10.10.20.10 | ✅ |
| CT 2011 | svc-mariadb | 10.10.20.11 | ✅ |
| CT 2012 | svc-gitea | 10.10.20.12:22 | ✅ |
| CT 4030 | web-netbox | 10.10.40.30 | ✅ |
| CT 4040 | web-snipeit | 10.10.40.40 | ✅ |
| CT 10015 | ops-semaphore | 10.10.100.15 | ✅ |

**Hinweis:** Gitea verwendet Port 2222 für Git-SSH, aber Port 22 für Standard-SSH.

## SSH-Key zu Semaphore hinzufügen (Web-UI)

### Schritt 1: Login

1. Gehe zu http://10.10.100.15:3000
2. Login mit Admin-Account (kolja oder ralf)

### Schritt 2: Key Store öffnen

1. Navigiere zu **Key Store** im Hauptmenü
2. Klicke auf **+ New Key**

### Schritt 3: Key-Details eingeben

**Name:** `ralf-ansible`

**Type:** `SSH Key`

**Login Optional (Username):** `root`

**SSH Private Key:** *(Kopiere den Inhalt von `/root/.ssh/semaphore/ralf-ansible`)*

```bash
# Private Key anzeigen:
cat /root/.ssh/semaphore/ralf-ansible
```

**Output:**
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACDdMaohNEByXJLr8/HR3Exgq158HPMr5qJOXOTw8DOzyQAAAKDHu6eTx7un
kwAAAAtzc2gtZWQyNTUxOQAAACDdMaohNEByXJLr8/HR3Exgq158HPMr5qJOXOTw8DOzyQ
AAAEAGFDyMH1Uv1yqL7kVmF5ORuvsfVdYi4OUGbv+aBM7h/t0xqiE0QHJckuvz8dHcTGCr
Xnwc8yvmok5c5PDwM7PJAAAAFnJhbGYtYW5zaWJsZUBzZW1hcGhvcmUBAgMEBQYH
-----END OPENSSH PRIVATE KEY-----
```

### Schritt 4: Speichern

1. Klicke auf **Create**
2. Key sollte jetzt in der Liste erscheinen

## SSH-Key testen

Nach dem Hinzufügen in Semaphore:

```bash
# Test SSH-Verbindung vom Semaphore-Container
pct exec 10015 -- ssh -i /root/.ssh/semaphore/ralf-ansible root@10.10.20.10 "hostname"
```

**Erwartete Ausgabe:** `svc-postgres`

## Ansible Inventory Configuration

Die SSH-Verbindung ist jetzt für Ansible konfiguriert:

```yaml
all:
  vars:
    ansible_user: root
    ansible_ssh_private_key_file: /root/.ssh/semaphore/ralf-ansible
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
```

## Troubleshooting

### SSH-Verbindung fehlschlägt

```bash
# Prüfe ob SSH-Server läuft
pct exec 2010 -- systemctl status ssh

# Prüfe authorized_keys
pct exec 2010 -- cat /root/.ssh/authorized_keys

# Teste Verbindung mit Verbose-Output
ssh -i /root/.ssh/semaphore/ralf-ansible -v root@10.10.20.10
```

### Key in Semaphore nicht akzeptiert

- Prüfe ob der komplette Key kopiert wurde (inkl. BEGIN/END Zeilen)
- Prüfe ob Username "root" eingetragen ist
- Prüfe ob Key-Type "SSH Key" ist (nicht "Login with password")

### Gitea SSH-Verbindung fehlschlägt

```bash
# Gitea: Port 22 für Standard-SSH, Port 2222 für Git-SSH
ssh -p 22 -i /root/.ssh/semaphore/ralf-ansible root@10.10.20.12 "hostname"
```

## Nächste Schritte

Nach dem Hinzufügen des Keys in Semaphore:

1. ✅ Repository-Verbindung zu Gitea hinzufügen (Task #48)
2. Environment Variables konfigurieren (Task #49)
3. Erste Pipeline testen

## Security Notes

- Private Key liegt nur auf Proxmox-Host und in Semaphore
- Key ist Ed25519 (moderne, sichere Cipher)
- Keine Passphrase (für automatisierte Deployments)
- Public Key in allen Containern in `/root/.ssh/authorized_keys`

## Backup

```bash
# Private Key backup
cp /root/.ssh/semaphore/ralf-ansible /root/ralf/secrets/ralf-ansible.key.backup
chmod 600 /root/ralf/secrets/ralf-ansible.key.backup
```

**⚠️ WICHTIG:** Private Keys gehören NICHT ins Git-Repository!
