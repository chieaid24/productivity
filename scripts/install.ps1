# Installs Productivity: discovers dependencies (installing AutoHotkey v2
# via winget when missing), writes the gitignored config.local.ini seeded
# from the standalone apps it replaces, migrates their state, registers the
# toast AUMID, retires the old apps' autostarts, registers the daemon in
# Startup, and starts it. Idempotent.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$AppId = 'Chieaid24.Productivity'

function Step($msg) { Write-Host "==> $msg" }
function Warn($msg) { Write-Warning $msg }

if ($env:OS -ne 'Windows_NT') { throw 'This installer must run on Windows.' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git is required but was not found on PATH.' }

function Invoke-RepoGit([string[]]$GitArgs) {
    & git -C $RepoRoot @GitArgs *> $null
    return $LASTEXITCODE
}

function Find-AutoHotkey {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey32.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey32.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

function Find-Brave {
    $cmd = Get-Command brave.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($hive in 'HKLM:', 'HKCU:') {
        $key = "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe"
        $path = (Get-ItemProperty $key -ErrorAction SilentlyContinue).'(default)'
        if ($path -and (Test-Path $path)) { return $path }
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'BraveSoftware\Brave-Browser\Application\brave.exe'),
        (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    return $null
}

# --- 1. AutoHotkey v2 -------------------------------------------------------
Step 'Checking AutoHotkey v2'
$ahk = Find-AutoHotkey
if (-not $ahk) {
    Step 'Installing AutoHotkey v2 with winget'
    $common = @('--source', 'winget', '--silent', '--disable-interactivity',
                '--accept-package-agreements', '--accept-source-agreements')
    & winget install --id AutoHotkey.AutoHotkey --exact --scope user @common
    if ($LASTEXITCODE -ne 0) { & winget install --id AutoHotkey.AutoHotkey --exact @common }
    $ahk = Find-AutoHotkey
}
if (-not $ahk) { throw 'AutoHotkey v2 was not found and could not be installed.' }
Step "AutoHotkey: $ahk"

# --- 2. Browsers and Outlook (best effort; each only affects one service) ---
$brave = Find-Brave
if ($brave) { Step "Brave: $brave" } else { Warn 'Brave not found; the Morning Dashboard service needs it.' }
$classicOutlook = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE' -ErrorAction SilentlyContinue).'(default)'
if ($classicOutlook -and -not (Test-Path $classicOutlook)) { $classicOutlook = $null }
$newOutlookAppId = $null
$pkg = Get-AppxPackage Microsoft.OutlookForWindows -ErrorAction SilentlyContinue
if ($pkg) { $newOutlookAppId = "$($pkg.PackageFamilyName)!Microsoft.OutlookforWindows" }

# --- 3. Local config, seeded from the apps this suite replaces ---------------
$localConfig = Join-Path $RepoRoot 'config.local.ini'
$altLocalConfig = Join-Path $RepoRoot 'config\config.local.ini'
if ((Test-Path $localConfig) -or (Test-Path $altLocalConfig)) {
    Step 'config.local.ini already exists; leaving it untouched'
} else {
    Step 'Writing config.local.ini (migrating old app settings)'
    $timer = $null
    $timerPath = Join-Path $env:LOCALAPPDATA 'ProductivityTimer\settings.json'
    if (Test-Path $timerPath) {
        try { $timer = Get-Content $timerPath -Raw | ConvertFrom-Json } catch { Warn "Could not read $timerPath" }
    }
    $tracker = $null
    $trackerPath = Join-Path $env:LOCALAPPDATA 'CCUsageTracker\settings.json'
    if (Test-Path $trackerPath) {
        try { $tracker = Get-Content $trackerPath -Raw | ConvertFrom-Json } catch { Warn "Could not read $trackerPath" }
    }
    $monitorModes = @('mouse', 'foreground', 'primary')
    $prefer = if ($newOutlookAppId) { 'new' } else { 'classic' }
    @"
[Timer]
IntervalMinutes=$(if ($timer) { $timer.interval_minutes } else { 20 })
Message=$(if ($timer) { $timer.message } else { 'Water, breathe, flat, posture' })
Sound=$(if ($timer) { $timer.sound } else { 'default' })
CustomSound=$(if ($timer -and $timer.custom_sound) { $timer.custom_sound })

[Dashboard]
Hotkey=^!m

[Dashboard.Brave]
Executable=$brave
ProfileDirectory=

[Dashboard.Outlook]
Prefer=$prefer
Executable=$classicOutlook
AppId=$newOutlookAppId

[Dashboard.Calendar]
Url=https://calendar.google.com/calendar/u/0/r/day

[Dashboard.Tasks]
Url=https://calendar.google.com/calendar/u/0/r/tasks

[Dashboard.Gmail]
Url1=https://mail.google.com/mail/u/1/#inbox
Url2=https://mail.google.com/mail/u/0/#inbox
Url3=https://mail.google.com/mail/u/2/#inbox

[Dashboard.Monitors]
LeftMonitor=
RightMonitor=

[FocusSwitcher]
HotkeyLeft=^!Left
HotkeyRight=^!Right
MoveMouse=0
WrapMonitors=1

[UsageTracker]
Hotkey=^!u
ClaudeUrl=$(if ($tracker) { $tracker.ClaudeUsageUrl } else { 'https://claude.ai/settings/usage' })
CodexUrl=$(if ($tracker) { $tracker.CodexUsageUrl } else { 'https://chatgpt.com/codex/settings/usage' })
ChromeExecutable=$(if ($tracker -and $tracker.ChromeExecutablePath) { $tracker.ChromeExecutablePath })
MonitorSelection=$(if ($tracker) { $monitorModes[[int]$tracker.MonitorSelection] } else { 'mouse' })
WidthPercent=$(if ($tracker) { $tracker.WidthPercent } else { 86 })
HeightPercent=$(if ($tracker) { $tracker.HeightPercent } else { 80 })
Gap=$(if ($tracker) { $tracker.Gap } else { 12 })
OuterMargin=$(if ($tracker) { $tracker.OuterMargin } else { 24 })
KeepOnTop=$(if ($tracker -and $tracker.KeepWindowsOnTop) { 1 } else { 0 })
"@ | Set-Content -Path $localConfig -Encoding ASCII
}

# Migrate the timer's last-trigger state once.
$timerState = Join-Path $env:LOCALAPPDATA 'ProductivityTimer\state.json'
$suiteTimerState = Join-Path $RepoRoot '.state\timer.ini'
if ((Test-Path $timerState) -and -not (Test-Path $suiteTimerState)) {
    try {
        $iso = (Get-Content $timerState -Raw | ConvertFrom-Json).last_triggered
        $stamp = [DateTimeOffset]::Parse($iso).UtcDateTime.ToString('yyyyMMddHHmmss')
        New-Item -ItemType Directory -Force -Path (Join-Path $RepoRoot '.state') | Out-Null
        "[State]`nLastTriggered=$stamp`n" | Set-Content -Path $suiteTimerState -Encoding ASCII
        Step 'Migrated last reminder trigger time'
    } catch { Warn 'Could not migrate the timer state; starting fresh.' }
}

# --- 4. Git hooks ---------------------------------------------------------------
Step 'Configuring repo-local git hooks'
$code = Invoke-RepoGit @('config', 'core.hooksPath', '.githooks')
if ($code -ne 0) { Warn 'Could not set core.hooksPath (git cannot use this checkout from Windows).' }

# --- 5. Toast AUMID ---------------------------------------------------------------
Step 'Registering toast application id'
$appDir = Join-Path $env:LOCALAPPDATA 'Productivity'
New-Item -ItemType Directory -Force -Path $appDir | Out-Null
$iconLocal = Join-Path $appDir 'app.ico'
Copy-Item (Join-Path $RepoRoot 'assets\productivity-running.ico') $iconLocal -Force
$aumidKey = "HKCU:\Software\Classes\AppUserModelId\$AppId"
New-Item -Path $aumidKey -Force | Out-Null
Set-ItemProperty -Path $aumidKey -Name DisplayName -Value 'Productivity'
Set-ItemProperty -Path $aumidKey -Name IconUri -Value $iconLocal

# --- 6. Retire the standalone apps ---------------------------------------------------
Step 'Retiring standalone app autostarts (binaries stay installed)'
Get-Process ProductivityTimer, CCUsageTracker -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -match 'FocusSwitcher\.ahk|dashboard\.ahk' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
foreach ($name in 'ProductivityTimer', 'CCUsageTracker') {
    Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
}
$startup = [Environment]::GetFolderPath('Startup')
foreach ($lnk in 'Focus Switcher.lnk', 'Morning Dashboard.lnk') {
    $p = Join-Path $startup $lnk
    if (Test-Path $p) { Remove-Item $p -Force }
}
Remove-Item 'HKCU:\Software\Classes\AppUserModelId\Chieaid24.ProductivityTimer' -Force -ErrorAction SilentlyContinue

# --- 7. Startup entry -------------------------------------------------------------
Step 'Registering daemon in Startup'
$script = Join-Path $RepoRoot 'src\productivity.ahk'
$launcher = Join-Path $appDir 'launcher.ahk'
@"
#Requires AutoHotkey v2.0
#NoTrayIcon
; Written by install.ps1. Waits for the repo to become reachable (a WSL
; checkout may still be starting at logon), then starts the daemon.
scriptPath := "$script"
deadline := A_TickCount + 120000
while A_TickCount < deadline {
    if FileExist(scriptPath) {
        Run '"' A_AhkPath '" "' scriptPath '"'
        ExitApp
    }
    Sleep 3000
}
ExitApp
"@ | Set-Content -Path $launcher -Encoding ASCII
$lnkPath = Join-Path $startup 'Productivity.lnk'
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = $ahk
$lnk.Arguments = '"' + $launcher + '"'
$lnk.Description = 'Productivity tray daemon'
$lnk.Save()
Step "Startup shortcut: $lnkPath"

# --- 8. (Re)start daemon ------------------------------------------------------------
Step 'Starting daemon'
Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" |
    Where-Object { $_.CommandLine -like '*productivity.ahk*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Process -FilePath $ahk -ArgumentList ('"' + $script + '"')

# --- 9. Privacy verification ---------------------------------------------------------
Step 'Running privacy verification'
& (Join-Path $PSScriptRoot 'verify-privacy.ps1')
if ($LASTEXITCODE -ne 0) { Warn 'Privacy verification reported problems; fix them before pushing.' }

Write-Host ''
Write-Host 'Productivity installed. It lives in the system tray.'
