# RUNBOOK (MVP Start)

## 1) MinIO LXC erstellen

```bash
cd stacks/030-minio-lxc
tofu init
tofu plan
tofu apply
```

## 2) MinIO Bucket für State anlegen

- Bucket: `ralf-state`
- Endpoint: `10.10.30.10:9000`

## 3) Bootstrap LXC erstellen

```bash
cd stacks/100-bootstrap-lxc
tofu init
tofu plan
tofu apply
```

## 4) Schnellchecks

- Container `minio` läuft
- Container `ralf-bootstrap` läuft
- SSH auf `10.10.100.10` möglich
- MinIO Bucket `ralf-state` erreichbar