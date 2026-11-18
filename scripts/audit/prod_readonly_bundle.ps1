#requires -Version 5.1
<#
  One-shot prod read-only bundle: STS -> SSM tunnel :5434 -> forensics -> backup -> AWS/pg_cron.
  Does NOT mutate RDS (read-only SQL, dry-run migrate, pg_dump, AWS describe-*).
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$LocalPort = 5434
$BastionId = 'i-0248ed3a2aad183be'
$Region = 'ap-south-1'
$MaxWaitSec = 60
$MaxRestarts = 3

$Global:TunnelProc = $null
$tsLog = Get-Date -Format 'yyyyMMdd-HHmmss'
$Global:TunnelLogOut = Join-Path $env:TEMP "doctornect-ssm-tunnel-$tsLog.out.log"
$Global:TunnelLogErr = Join-Path $env:TEMP "doctornect-ssm-tunnel-$tsLog.err.log"
$Global:Summary = [ordered]@{ started_at = (Get-Date).ToString('o'); steps = @(); failures = @() }

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Record-Step($name, $code, $note = '') { $Global:Summary.steps += @{ step = $name; exit = $code; note = $note } }

function Get-DotEnvValue([string]$Key) {
  $path = Join-Path $RepoRoot '.env'
  if (-not (Test-Path $path)) { throw ".env missing at $path" }
  foreach ($line in Get-Content $path -Encoding UTF8) {
    if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
    if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*)\s*$") {
      $v = $Matches[1].Trim()
      if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
      return $v
    }
  }
  throw "Missing $Key in .env"
}

function Test-TunnelUp {
  $t = Test-NetConnection -ComputerName 127.0.0.1 -Port $LocalPort -WarningAction SilentlyContinue
  return [bool]$t.TcpTestSucceeded
}

function Get-ListenerOwner() {
  $c = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { return $null }
  $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
  return $p
}

function Start-SsmTunnel([string]$RdsHost) {
  $owner = Get-ListenerOwner
  if ($owner) {
    if ($owner.ProcessName -match 'session-manager') {
      if (Test-TunnelUp) {
        Write-Host "Port $LocalPort already held by $($owner.ProcessName) (reuse, TCP OK)."
        return
      }
      Write-Host "Port $LocalPort held by $($owner.ProcessName) but TCP not ready — starting a new forward (leave stale plugin alone)."
    }
    throw "Port $LocalPort in use by PID $($owner.Id) process $($owner.ProcessName) — not session-manager-plugin. Free the port manually."
  }

  $args = @(
    'ssm', 'start-session',
    '--target', $BastionId,
    '--document-name', 'AWS-StartPortForwardingSessionToRemoteHost',
    '--parameters', "host=$RdsHost,portNumber=5432,localPortNumber=$LocalPort",
    '--region', $Region
  )
  $Global:TunnelProc = Start-Process -FilePath 'aws' -ArgumentList $args -PassThru `
    -RedirectStandardOutput $Global:TunnelLogOut -RedirectStandardError $Global:TunnelLogErr -WindowStyle Hidden
  Write-Host "Started SSM forward PID $($Global:TunnelProc.Id); logs: $($Global:TunnelLogOut)"

  $deadline = (Get-Date).AddSeconds($MaxWaitSec)
  while ((Get-Date) -lt $deadline) {
    if ($Global:TunnelProc.HasExited) {
      $tail = @((Get-Content $Global:TunnelLogErr -ErrorAction SilentlyContinue), (Get-Content $Global:TunnelLogOut -ErrorAction SilentlyContinue)) | Select-Object -Last 40
      throw "SSM process exited early. Log tail:`n$($tail -join "`n")"
    }
    if (Test-TunnelUp) { Write-Host "Tunnel ready on 127.0.0.1:$LocalPort"; return }
    Start-Sleep -Seconds 3
  }
  $tail = @((Get-Content $Global:TunnelLogErr -ErrorAction SilentlyContinue), (Get-Content $Global:TunnelLogOut -ErrorAction SilentlyContinue)) | Select-Object -Last 40
  throw "Tunnel not ready after ${MaxWaitSec}s. Log tail:`n$($tail -join "`n")"
}

function Stop-SsmTunnelIfOurs() {
  if ($Global:TunnelProc -and -not $Global:TunnelProc.HasExited) {
    Stop-Process -Id $Global:TunnelProc.Id -Force -ErrorAction SilentlyContinue
    Write-Host "Stopped SSM forward PID $($Global:TunnelProc.Id)"
  }
}

function Ensure-Tunnel([string]$RdsHost, [int]$RestartCount) {
  if (Test-TunnelUp) { return }
  if ($RestartCount -ge $MaxRestarts) { throw "Tunnel down after $MaxRestarts restarts" }
  Write-Host "Tunnel down; restart $($RestartCount + 1)/$MaxRestarts"
  Stop-SsmTunnelIfOurs
  Start-Sleep -Seconds 2
  Start-SsmTunnel $RdsHost
}

function Invoke-NodeStep([string]$Name, [string]$RelScript, [string[]]$ExtraArgs) {
  $script = Join-Path $RepoRoot $RelScript
  $all = @($script) + $ExtraArgs
  $p = Start-Process -FilePath 'node' -ArgumentList $all -WorkingDirectory $RepoRoot -Wait -PassThru -NoNewWindow
  return $p.ExitCode
}

function Mask-Host([string]$hostName) {
  if (-not $hostName) { return '(unset)' }
  if ($hostName.Length -le 12) { return '****' }
  return ($hostName.Substring(0, 6) + '****' + $hostName.Substring($hostName.Length - 4))
}

try {
  Write-Step 'AWS STS'
  $sts = aws sts get-caller-identity --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host $sts
    throw @"
AWS STS failed. Fix before retry:
  1) aws configure list
  2) aws sso login  (if using SSO profile)
  3) Or set AWS_PROFILE / credentials for account with ssm:StartSession on bastion $BastionId
"@
  }
  $id = $sts | ConvertFrom-Json
  Write-Host "STS Account=$($id.Account) Arn=$($id.Arn)"

  $ProdHost = (node -e "console.log(require('./scripts/lib/prod_rds_host_policy').resolveLogicalProdRdsHost())").Trim()
  $ProdDb = (node -e "require('./scripts/lib/bootstrap_root_env').loadRootEnv();const {getEnv}=require('./scripts/lib/env_loader');process.stdout.write(getEnv('PROD_RDS_DB')||'doctornect');").Trim()
  if (-not $ProdHost) { throw 'PROD_RDS_HOST missing in .env (loaded via node)' }

  # Session-only tunnel overrides (do not edit .env): correct bleed from 5442 / ssl disable
  $env:PROD_RDS_CONNECT_HOST = '127.0.0.1'
  $env:PROD_RDS_PORT = [string]$LocalPort
  $env:PROD_RDS_SSLMODE = 'verify-full'
  $env:PROD_RDS_HOST = $ProdHost
  $env:PROD_RDS_SSL_SERVERNAME = $ProdHost

  Write-Host "PROD_RDS_HOST=$(Mask-Host $ProdHost) PROD_RDS_DB=$ProdDb port=$LocalPort ssl=verify-full"

  Write-Step 'Port check'
  $listener = Get-ListenerOwner
  if ($listener -and $listener.ProcessName -notmatch 'session-manager') {
    throw "Port $LocalPort busy: $($listener.ProcessName) PID $($listener.Id)"
  }

  Write-Step 'Task 1: PROD env audit'
  $code = Invoke-NodeStep 'env_audit' 'scripts/audit/_prod_env_audit_readonly.js' @()
  if ($code -ne 0) { $Global:Summary.failures += 'env_audit' }

  $restart = 0
  Start-SsmTunnel $ProdHost
  Record-Step 'tunnel' 0

  Write-Step 'Task 1: auth probe (discrete pg params)'
  Ensure-Tunnel $ProdHost $restart
  $code = Invoke-NodeStep 'auth_probe' 'scripts/audit/_prod_auth_probe_readonly.js' @()
  if ($code -ne 0) { $Global:Summary.failures += 'auth_probe' }

  $runWithTunnel = {
    param($StepName, $Block)
    Ensure-Tunnel $ProdHost $restart
    & $Block
    $code = $LASTEXITCODE
    if (-not $code) { $code = 0 }
    Record-Step $StepName $code
    if ($code -ne 0) { $Global:Summary.failures += $StepName }
    return $code
  }

  Write-Step 'Task 2: greenfield forensics'
  $code = Invoke-NodeStep 'greenfield' 'scripts/audit/_prod_greenfield_readonly.js' @()
  if ($null -eq $code) { $code = 0 }
  if ($code -ne 0) { $Global:Summary.failures += 'greenfield' }

  Write-Step 'Task 2: bootstrap gaps + verdict'
  $code = Invoke-NodeStep 'bootstrap_gap' 'scripts/audit/_prod_bootstrap_gap_readonly.js' @()
  if ($code -ne 0) { $Global:Summary.failures += 'bootstrap_gap' }

  Write-Step 'Task 2: prod_rds_preflight_readonly'
  $code = Invoke-NodeStep 'preflight' 'scripts/db/prod_rds_preflight_readonly.js' @()
  if ($code -ne 0) { $Global:Summary.failures += 'preflight' }

  Write-Step 'Task 2: migrate dry-run'
  Ensure-Tunnel $ProdHost $restart
  Push-Location $RepoRoot
  & node scripts/db/migrate.js --target=production --dry-run --confirm-live-data --confirm-db=$ProdDb --confirm=$ProdHost
  $code = $LASTEXITCODE
  Pop-Location
  Record-Step 'migrate_dry_run' $code
  if ($code -ne 0) { $Global:Summary.failures += 'migrate_dry_run' }

  Write-Step 'Task 2: pg_dump v2'
  $date = Get-Date -Format 'yyyy-MM-dd'
  $backupDir = "C:\Users\khije\Backups\doctornect-prod-$date-v2"
  Ensure-Tunnel $ProdHost $restart
  Push-Location $RepoRoot
  & node scripts/audit/_prod_backup_once.js $backupDir
  $code = $LASTEXITCODE
  Pop-Location
  Record-Step 'pg_dump' $code
  if ($code -eq 0 -and (Test-Path $backupDir)) {
    $dump = Join-Path $backupDir 'doctornect_prod.dump'
    if (Test-Path $dump) {
      $bin = 'C:\Program Files\PostgreSQL\18\bin\pg_restore.exe'
      $list = & $bin --list $dump 2>&1
      $toc = ($list | Measure-Object -Line).Lines
      $hdr = $list | Select-Object -First 15
      Write-Host "BACKUP path=$backupDir size=$((Get-Item $dump).Length) toc_lines=$toc"
      Write-Host 'TOC header (check RDS hostname):'
      $hdr | ForEach-Object { Write-Host $_ }
    }
  } else { $Global:Summary.failures += 'pg_dump' }

  Write-Step 'Task 3: AWS RDS describe (read-only)'
  $oldEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $instances = aws rds describe-db-instances --region $Region --output json 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host $instances
    $Global:Summary.failures += 'aws_describe_db_instances'
  } else {
    $parsed = $instances | ConvertFrom-Json
    $match = $parsed.DBInstances | Where-Object { $_.Endpoint.Address -eq $ProdHost } | Select-Object -First 1
    if ($match) {
      Write-Host (@"
RDS_INSTANCE $($match.DBInstanceIdentifier)
EngineVersion=$($match.EngineVersion)
BackupRetention=$($match.BackupRetentionPeriod)
PreferredBackupWindow=$($match.PreferredBackupWindow)
MultiAZ=$($match.MultiAZ)
DBParameterGroup=$($match.DBParameterGroups[0].DBParameterGroupName)
ParameterApplyStatus=$($match.DBParameterGroups[0].ParameterApplyStatus)
PendingModified=$($match.PendingModifiedValues | ConvertTo-Json -Compress)
"@)
      $pgName = $match.DBParameterGroups[0].DBParameterGroupName
      $pg = aws rds describe-db-parameters --db-parameter-group-name $pgName --region $Region --output json 2>&1
      if ($LASTEXITCODE -eq 0) {
        $pgo = $pg | ConvertFrom-Json
        $isDefault = $pgName -match 'default'
        foreach ($want in @('shared_preload_libraries', 'cron.database_name')) {
          $par = $pgo.Parameters | Where-Object { $_.ParameterName -eq $want } | Select-Object -First 1
          if ($par) { Write-Host "PARAM $want = $($par.ParameterValue) apply=$($par.ApplyMethod) pending=$($par.ApplyType)" }
          else { Write-Host "PARAM $want = (not in group)" }
        }
        Write-Host "PARAM_GROUP is_default_pattern=$isDefault name=$pgName"
      }
    } else {
      Write-Host 'Could not match DB instance by PROD_RDS_HOST endpoint (listing identifiers only):'
      $parsed.DBInstances | ForEach-Object { Write-Host "  $($_.DBInstanceIdentifier) $($_.Endpoint.Address)" }
    }
    $snap = aws rds describe-db-snapshots --region $Region --output json 2>&1
    if ($LASTEXITCODE -eq 0) {
      $so = $snap | ConvertFrom-Json
      $auto = $so.DBSnapshots | Where-Object { $_.SnapshotType -eq 'automated' } | Sort-Object SnapshotCreateTime -Descending | Select-Object -First 1
      $man = $so.DBSnapshots | Where-Object { $_.SnapshotType -eq 'manual' } | Sort-Object SnapshotCreateTime -Descending | Select-Object -First 1
      if ($auto) { Write-Host "LATEST_AUTOMATED_SNAPSHOT $($auto.DBSnapshotIdentifier) at $($auto.SnapshotCreateTime)" }
      if ($man) { Write-Host "LATEST_MANUAL_SNAPSHOT $($man.DBSnapshotIdentifier) at $($man.SnapshotCreateTime)" }
    }
  }

  Write-Step 'Task 3: pg_cron SQL'
  Ensure-Tunnel $ProdHost $restart
  $code = Invoke-NodeStep 'pg_cron_sql' 'scripts/audit/_prod_pg_cron_sql_readonly.js' @()
  if ($code -ne 0) { $Global:Summary.failures += 'pg_cron_sql' }

  Write-Step 'Task 4: bastion SSM read-only probe'
  $rdsForNc = $ProdHost
  $ssmParamFile = Join-Path $env:TEMP "doctornect-ssm-cmd-$((Get-Date).ToUniversalTime().ToString('HHmmss')).json"
  @{
    commands = @(
      'node -v 2>&1 || echo NODE_MISSING',
      'git --version 2>&1 || echo GIT_MISSING',
      'tmux -V 2>&1 || echo TMUX_MISSING',
      'whoami',
      'df -h /',
      "nc -zv $rdsForNc 5432 2>&1 || echo NC_FAILED"
    )
  } | ConvertTo-Json | Set-Content -Encoding UTF8 $ssmParamFile
  $paramUri = 'file://' + ($ssmParamFile -replace '\\', '/')
  $send = aws ssm send-command --region $Region --instance-ids $BastionId --document-name "AWS-RunShellScript" `
    --parameters $paramUri --output json 2>&1
  if ($LASTEXITCODE -eq 0) {
    $cmdId = ($send | ConvertFrom-Json).Command.CommandId
    Write-Host "SSM CommandId=$cmdId"
    Start-Sleep -Seconds 8
    aws ssm get-command-invocation --region $Region --command-id $cmdId --instance-id $BastionId --output json 2>&1
  } else {
    Write-Host $send
    $Global:Summary.failures += 'bastion_send_command'
  }

  Write-Step 'Task 4: bastion metadata (read-only AWS API)'
  aws ec2 describe-instances --instance-ids $BastionId --region $Region `
    --query "Reservations[0].Instances[0].{State:State.Name,Subnet:SubnetId,VpcId:VpcId,PrivateIp:PrivateIpAddress,Platform:PlatformDetails}" --output json 2>&1
  aws ssm describe-instance-information --region $Region `
    --filters "Key=InstanceIds,Values=$BastionId" --query "InstanceInformationList[0].{Ping:PingStatus,Platform:PlatformName,Agent:AgentVersion}" --output json 2>&1
  $ErrorActionPreference = $oldEap

  $Global:Summary.ended_at = (Get-Date).ToString('o')
  $Global:Summary.failures = @($Global:Summary.failures | Select-Object -Unique)
  Write-Step 'BUNDLE SUMMARY'
  $Global:Summary | ConvertTo-Json -Depth 5
  if ($Global:Summary.failures.Count -gt 0) { exit 2 }
} catch {
  Write-Host "BUNDLE_ABORT: $_" -ForegroundColor Red
  if (Test-Path $Global:TunnelLogErr) { Get-Content $Global:TunnelLogErr | Select-Object -Last 20 }
  if (Test-Path $Global:TunnelLogOut) { Get-Content $Global:TunnelLogOut | Select-Object -Last 20 }
  exit 1
} finally {
  Stop-SsmTunnelIfOurs
}