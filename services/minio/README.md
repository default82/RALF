# MinIO
S3-kompatibler Object Storage als systemd service (ohne Docker).

Ports:
- API: 9000/tcp
- Console: 9001/tcp

Secrets:
- werden zur Laufzeit generiert und lokal in `stacks/minio-lxc/keys/minio.env` abgelegt (nicht im Git).
