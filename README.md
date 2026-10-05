# Schedule-Reboot

PowerShell script that schedules a single reboot of a Windows PC at a given time, waking it from sleep if needed. Designed to be run as SYSTEM from an RMM (e.g. NinjaOne), but works from any elevated session.

## How it works

- Registers a one-time scheduled task (`ScheduledReboot`) running as SYSTEM with "wake to run" enabled.
- Enables wake timers on AC power for the current power plan (needed on Modern Standby devices).
- When the task fires:
  - If it is more than 90 minutes late (PC was off or could not wake), the reboot is skipped.
  - If Windows Update, setup, DISM or SFC is busy, it waits up to 60 minutes (checking every 5 minutes), then skips if still busy.
  - Otherwise it shows a 2-minute on-screen warning and restarts.
- Logs to `C:\ProgramData\ScheduledReboot\reboot.log`.

## Usage

Set the `RebootTime` variable (environment variable or NinjaOne script variable, type String):

| Value              | Result                                                    |
|--------------------|-----------------------------------------------------------|
| `21:30` or `21h30` | Today at 21:30, or tomorrow if that time has passed       |
| `2026-10-05 21:30` | That date and time                                        |
| Unix epoch (s/ms)  | That moment (NinjaOne date/time variables)                |
| `cancel`           | Removes a pending scheduled reboot                        |

The target must be more than 2 minutes and less than 7 days in the future.

Running manually from an elevated PowerShell:

```powershell
$env:RebootTime = '21:30'
.\Schedule-Reboot.ps1
```

## Requirements

- Windows 10/11
- Administrator or SYSTEM privileges
