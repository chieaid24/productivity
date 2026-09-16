# Productivity

One AutoHotkey v2 process in the Windows system tray that replaces four separate tray apps: interval break reminders (the headline), plus a two-monitor morning dashboard, monitor-to-monitor focus switching, and Claude/Codex usage popups as toggleable services.

| Service | Hotkey | What it does |
|---|---|---|
| Reminders | - | Windows toast every N minutes with your message and sound |
| Morning Dashboard | Ctrl+Alt+M | Outlook over Gmail on the left monitor, Calendar and schedule image split on the right |
| Focus Switcher | Ctrl+Alt+Left/Right | Moves focus to the last-used window on the adjacent monitor |
| CC Usage Tracker | Ctrl+Alt+U | Two frameless Chrome popups with the Claude and Codex usage pages |

Right-click the tray icon to pause reminders, open each service's submenu, disable a service, or reach its settings. Exit dismisses the app until your next sign-in.

## Installation

Requires Windows 11. The installer fetches AutoHotkey v2 with winget when missing, migrates settings from the standalone Productivity Timer, CC Usage Tracker, Focus Switcher, and Morning Dashboard installs it replaces, and removes their autostart entries (their binaries stay).

1. Clone this repository.

   ```powershell
   git clone https://github.com/chieaid24/productivity.git
   ```

2. Run the installer (the schedule image argument is only needed on a machine without a previous Morning Dashboard install).

   ```powershell
   .\scripts\install.ps1 -ScheduleImagePath "C:\Users\you\Pictures\schedule.jpg"
   ```

The daemon starts immediately and registers itself in your Startup folder.

## Configuration

Everything lives in one gitignored `config.local.ini`: reminder interval, message, and sound; dashboard URLs, browser, and monitors; focus-switcher hotkeys; usage popup sizing. The reminder and usage-tracker submenus have settings dialogs that edit it for you; the rest is a text file away via "Open config file" in the tray menu. The schedule image stays in the gitignored `.private/` folder and never reaches Git history; a pre-commit hook, `scripts\verify-privacy.ps1`, and CI enforce this. Remove everything with `.\scripts\uninstall.ps1`.
