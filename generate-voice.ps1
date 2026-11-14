<#
  توليد صوت وليد (صوت طفل) لكل جمل voice_lines.csv عبر Fish Audio
  Generates audio/1.mp3 ... audio/39.mp3 from voice_lines.csv using a Fish Audio child voice.

  Usage (PowerShell, in this folder):
    $env:FISH_API_KEY = "your-key"            # from https://fish.audio -> API keys
    .\generate-voice.ps1                       # all missing lines, free model
    .\generate-voice.ps1 -Model s2.1-pro       # paid model (needed for commercial use)
    .\generate-voice.ps1 -Only 6,7 -Force      # regenerate specific lines
    .\generate-voice.ps1 -VoiceId <id>         # try a different voice from fish.audio

  If Windows blocks the script:  powershell -ExecutionPolicy Bypass -File .\generate-voice.ps1
#>
param(
  [string]$ApiKey = $env:FISH_API_KEY,
  # "صوت طفل صغير" — young Arabic male voice for children's content (fish.audio/m/20f56b7dc5fd4d219cc1611ec2a3b4a6)
  [string]$VoiceId = '20f56b7dc5fd4d219cc1611ec2a3b4a6',
  [ValidateSet('s2.1-pro-free','s2.1-pro','s2-pro','drama-3')]
  [string]$Model = 's2.1-pro-free',
  [double]$Speed = 1.0,
  [string[]]$Only,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
if (-not $ApiKey) { Write-Error 'No API key. Set $env:FISH_API_KEY = "..." or pass -ApiKey.'; exit 1 }

$root = $PSScriptRoot
$out  = Join-Path $root 'audio'
New-Item -ItemType Directory -Force $out | Out-Null
$lines = Import-Csv (Join-Path $root 'voice_lines.csv') -Encoding UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -Only may arrive as "2,11" (one string, when run with -File) or as 2,11 (array) - accept both
$OnlyN = @($Only | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
if ($Only -and -not $OnlyN.Count) { Write-Error "Could not read -Only '$Only'. Example: -Only 2,11"; exit 1 }
if ($OnlyN.Count) { Write-Host ("Only lines: " + ($OnlyN -join ', ')) }

$ok = 0; $fail = 0; $skip = 0
foreach ($l in $lines) {
  $n = [int]($l.file -replace '\.mp3$','')
  if ($OnlyN.Count -and ($OnlyN -notcontains $n)) { continue }
  $dest = Join-Path $out $l.file
  $tmp  = "$dest.part"
  if ((Test-Path $dest) -and -not $Force) { $skip++; continue }

  $body = @{
    text         = $l.text
    reference_id = $VoiceId
    format       = 'mp3'
    mp3_bitrate  = 128
    normalize    = $true
    latency      = 'normal'
    prosody      = @{ speed = $Speed; volume = 0; normalize_loudness = $true }
  } | ConvertTo-Json -Depth 4

  Write-Host ("[{0}/{1}] {2}" -f $n, $lines.Count, $l.text)
  try {
    Invoke-WebRequest -Uri 'https://api.fish.audio/v1/tts' -Method Post -UseBasicParsing `
      -Headers @{ Authorization = "Bearer $ApiKey"; model = $Model } `
      -ContentType 'application/json; charset=utf-8' `
      -Body ([Text.Encoding]::UTF8.GetBytes($body)) -OutFile $tmp -TimeoutSec 120
    if ((Get-Item $tmp).Length -lt 1000) { throw "response too small - not audio" }
    Move-Item -Force $tmp $dest   # replace the old file only after a good download
    $ok++
  } catch {
    $msg = $_.Exception.Message
    if ($_.Exception.Response) {
      try { $msg += ' | ' + (New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
    }
    Write-Warning "  failed: $msg"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }   # keep any existing good file
    $fail++
    if ($msg -match '401|402') { Write-Warning 'Check your API key / account balance. Stopping.'; break }
  }
}
Write-Host "Done. generated=$ok skipped(existing)=$skip failed=$fail  ->  $out"
