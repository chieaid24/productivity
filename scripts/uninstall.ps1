# Uninstalls Productivity: stops the daemon and the dashboard's browsers,
# removes the Startup entry, launcher, dashboard browser data, toast
# registration, and runtime state. Keeps .private\ unless
# -RemovePrivateData is given. Does not touch the standalone apps this
# suite replaced.

[CmdletBinding()]
param(
    [switch]$RemovePrivateData
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

function Step($msg) { Write-Host "==> $msg" }

Step 'Stopping daemon'
Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -like '*productivity.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Step 'Stopping dashboard browsers'
$dashboardData = Join-Path $env:LOCALAPPDATA 'Productivity\Dashboard'
$browsers = @(Get-CimInstance Win32_Process -Filter "Name = 'brave.exe' OR Name = 'chrome.exe'" |
    Where-Object { $_.CommandLine -like "*$dashboardData*" })
foreach ($p in $browsers) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
if ($browsers) { Wait-Process -Id $browsers.ProcessId -Timeout 10 -ErrorAction SilentlyContinue }

Step 'Removing Startup entry, launcher, and dashboard browser data'
$lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Productivity.lnk'
if (Test-Path $lnkPath) { Remove-Item $lnkPath -Force }
$appDir = Join-Path $env:LOCALAPPDATA 'Productivity'
if (Test-Path $appDir) { Remove-Item $appDir -Recurse -Force }

Step 'Removing toast registration'
Remove-Item 'HKCU:\Software\Classes\AppUserModelId\Chieaid24.Productivity' -Force -ErrorAction SilentlyContinue

Step 'Removing runtime state'
$stateDir = Join-Path $RepoRoot '.state'
if (Test-Path $stateDir) { Remove-Item $stateDir -Recurse -Force }

if ($RemovePrivateData) {
    Step 'Removing private data'
    $privateDir = Join-Path $RepoRoot '.private'
    if (Test-Path $privateDir) { Remove-Item $privateDir -Recurse -Force }
} else {
    Step 'Keeping .private\ (use -RemovePrivateData to delete it)'
}

Write-Host 'Productivity uninstalled.'
