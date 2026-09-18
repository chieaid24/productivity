# Productivity

Tray application containing my automation scripts.

| Service | What it does |
|---|---|
| Reminders | Toast every interval with your message and sound |
| Morning Dashboard | Opens Todoist and emails over Outlook, google calendar, a schedule image, and a bookmarks folder in a Chrome window |
| Focus Switcher | Moves focus to an adjacent monitor |
| CC Usage Tracker | Quickly check your Claude and Codex usage limits |


## Installation

Requires Windows 11. 

1. Clone this repository.

   ```powershell
   git clone https://github.com/chieaid24/productivity.git
   ```

2. Run the installer (with an image path you wish to open with your morning dashboard).

   ```powershell
   .\scripts\install.ps1 -ScheduleImagePath "C:\Users\you\Pictures\schedule.jpg"
   ```
