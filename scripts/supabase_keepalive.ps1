# Supabase keep-alive ping for the TravelLog project.
#
# Free-tier Supabase projects pause after ~7 days with no API activity. This
# script makes one tiny REST request so the inactivity timer keeps resetting.
# It's meant to be run daily by a Windows Scheduled Task.
#
# The publishable key is a client key (safe to keep here); every table it can
# reach is still gated by the project's row level security policies.

$ErrorActionPreference = 'Stop'

$base = 'https://ystuycqwumhhhapdsuss.supabase.co/rest/v1'
$key  = 'sb_publishable_Yybepofpr5GTQEiXFIXC7Q_RpadLkZC'
$headers = @{ apikey = $key; Authorization = "Bearer $key" }

$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$log = Join-Path $logDir 'keepalive.log'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

try {
    $r = Invoke-WebRequest -Uri "$base/trips?select=id&limit=1" `
        -Headers $headers -UseBasicParsing -TimeoutSec 30
    Add-Content -Path $log -Value "$stamp  OK  HTTP $($r.StatusCode)" -Encoding utf8
} catch {
    $code = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 'no-response' }
    Add-Content -Path $log -Value "$stamp  FAIL  $code  $($_.Exception.Message)" -Encoding utf8
}

# Keep the log from growing forever — last 200 lines only.
if (Test-Path $log) {
    $tail = Get-Content $log -Tail 200
    Set-Content -Path $log -Value $tail -Encoding utf8
}
