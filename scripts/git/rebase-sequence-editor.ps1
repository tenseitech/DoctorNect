param([string]$TodoFile)
$lines = Get-Content $TodoFile
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '\b91bd445\b') {
    $lines[$i] = $lines[$i] -replace '^pick ', 'reword '
  }
  if ($lines[$i] -match '\bf6e690f\b') {
    $lines[$i] = $lines[$i] -replace '^pick ', 'edit '
  }
}
Set-Content -Path $TodoFile -Value $lines
