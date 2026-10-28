# tools/rojo_serve_watchdog.ps1
# Supervisor for hotfrog's own `rojo serve --port 34873`: relaunches it after a crash.
# Ported from scare's tools/rojo_serve_watchdog.ps1. Start detached so it outlives the shell:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','"H:\Roblox Projects\hotfrog\tools\rojo_serve_watchdog.ps1"'
param(
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot),
    [string]$RojoExe    = "$env:USERPROFILE\.rokit\bin\rojo.exe",
    [int]$Port          = 34873,
    [int]$RestartDelay  = 3,
    [string]$LogFile    = "$env:TEMP\hotfrog_rojo_serve_watchdog.log"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $RojoExe)) {
    $RojoExe = (Get-Command rojo -ErrorAction SilentlyContinue).Source
    if (-not $RojoExe) { throw "rojo.exe not found. Install via rokit or add rojo to PATH." }
}
Set-Location $ProjectDir
$backoff = $RestartDelay
while ($true) {
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] starting rojo serve --port $Port"
    $p = Start-Process -FilePath $RojoExe -ArgumentList @("serve", "--port", "$Port") `
        -WorkingDirectory $ProjectDir -NoNewWindow -PassThru -Wait
    Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] rojo exited with code $($p.ExitCode)"
    if ($p.ExitCode -eq 0) { break }
    Start-Sleep -Seconds $backoff
    $backoff = [Math]::Min($backoff + 2, 30)
}
