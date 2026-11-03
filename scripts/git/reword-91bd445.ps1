param([string]$MsgFile)
@(
  'chore(audit): ignore local JSONL test reporter artifacts'
  ''
) | Set-Content -Path $MsgFile -Encoding utf8
