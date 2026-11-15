# Fail if a release AAB still embeds *.supabase.co (staging cloud) strings.
param(
    [string]$AabPath = (Join-Path $PSScriptRoot '..\build\app\outputs\bundle\release\app-release.aab')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AabPath)) {
    throw "AAB not found: $AabPath"
}

$bytes = [System.IO.File]::ReadAllBytes($AabPath)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$hits = [regex]::Matches($text, 'https?://[a-z0-9.-]+\.supabase\.co', 'IgnoreCase')
if ($hits.Count -gt 0) {
  throw "FAIL: found $($hits.Count) supabase.co URL substring(s) in AAB."
}

$size = (Get-Item -LiteralPath $AabPath).Length
Write-Host "PASS: no supabase.co URLs in AAB ($size bytes)."
exit 0