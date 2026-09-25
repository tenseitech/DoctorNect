$config = Get-Content "$env:USERPROFILE\.config\configstore\firebase-tools.json" -Raw | ConvertFrom-Json
$env:CLOUDSDK_AUTH_ACCESS_TOKEN = $config.tokens.access_token

Set-Location -Path "$PSScriptRoot\..\gcp-msg91-proxy"

gcloud run deploy msg91-proxy `
  --source . `
  --region asia-south1 `
  --project medibond-45fad `
  --vpc-connector msg91-connector `
  --vpc-egress all-traffic `
  --set-secrets "MSG91_AUTH_KEY=MSG91_AUTH_KEY:latest" `
  --set-secrets "PROXY_SECRET=PROXY_SECRET:latest" `
  --allow-unauthenticated `
  --platform managed `
  --quiet
