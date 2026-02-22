# Bootstrap MinIO (v1)

## Voraussetzungen
- Host erreichbar
- DNS/IP bekannt
- Storage Mount vorhanden (optional)

## Secrets (NICHT im Repo)
Folgende Werte müssen als Env bereitgestellt werden:
- MINIO_ROOT_USER
- MINIO_ROOT_PASSWORD

## Deploy
- via Ansible: ansible/playbooks/minio.yml

## Verify
- curl http://<host>:9000/minio/health/live
- curl http://<host>:9000/minio/health/ready
