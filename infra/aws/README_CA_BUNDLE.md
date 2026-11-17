# AWS RDS TLS CA bundle

Operator-only file (not committed with secrets). Scripts expect:

`infra/aws/global-bundle.pem`

## Download (global RDS CA)

```powershell
cd c:\Users\khije\Downloads\DoctorNect\doctor
New-Item -ItemType Directory -Force -Path infra\aws | Out-Null
Invoke-WebRequest -Uri "https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem" -OutFile "infra\aws\global-bundle.pem"
```

Point repo root `.env`:

```ini
PROD_RDS_SSL_ROOT_CERT=infra/aws/global-bundle.pem
PROD_RDS_SSLMODE=verify-full
```

When using **SSM port forward** to `127.0.0.1`, keep `PROD_RDS_SSL_SERVERNAME` (or `PROD_RDS_HOST`) set to the **real** `*.rds.amazonaws.com` hostname so certificate validation succeeds.
