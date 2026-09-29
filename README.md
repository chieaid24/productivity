# Productivity

Tray application containing my automation scripts.

| Service | What it does |
|---|---|
| Reminders | Toast every interval with your message and sound |
| Morning Dashboard | Opens three Gmail inboxes over Outlook, Google Calendar in day view, and a Google Calendar tasks view, with a bookmarks folder in a Chrome window. Adapts to one or two monitors. |
| Focus Switcher | Moves focus to an adjacent monitor |
| CC Usage Tracker | Quickly check your Claude and Codex usage limits |


## Installation

Requires Windows 11. 

1. Clone this repository.

   ```powershell
   git clone https://github.com/chieaid24/productivity.git
   ```

2. Run the installer.

   ```powershell
   .\scripts\install.ps1
   ```

3. Sign in once. The dashboard runs Brave and Chrome from their own data folders, so they start without your everyday logins. Press Ctrl+Alt+M, then sign in to your Google accounts in the Gmail window. Google numbers accounts in sign-in order, so sign in to the account that should be `/u/0` first, then `/u/1`, then `/u/2`. Sign in to any bookmarked sites that need it in the minimized Chrome window.
