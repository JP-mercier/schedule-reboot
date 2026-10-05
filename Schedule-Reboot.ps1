<#
    Schedule ONE reboot of this PC at a set time, waking it from sleep if needed. Run as SYSTEM (e.g. from NinjaOne).
    Script variable / environment variable (String) named  RebootTime :
       21:30              -> today at 21:30 (tomorrow if 21:30 has already passed)
       2026-10-05 21:30   -> that date and time
       cancel             -> remove a scheduled reboot
    Safety:
    - If the PC could not wake and the time passes by more than 90 min, the reboot is SKIPPED (never a surprise
      reboot in the morning when someone turns the PC on).
    - Waits (up to 60 min) while Windows is installing an update, or setup/DISM/SFC is running.
    - Shows a 2-minute warning on screen before restarting. Log: C:\ProgramData\ScheduledReboot\reboot.log
#>
$Base = 'C:\ProgramData\ScheduledReboot'
$Task = 'ScheduledReboot'
$Job  = Join-Path $Base 'scheduled-reboot-job.ps1'
New-Item -ItemType Directory -Force $Base | Out-Null
$raw = "$env:RebootTime".Trim()
"$env:COMPUTERNAME | RebootTime = '$raw'"

if ($raw -match '^(cancel|annuler|none)$') {
    Unregister-ScheduledTask -TaskName $Task -Confirm:$false -EA SilentlyContinue
    "Scheduled reboot cancelled (if there was one)."; return
}
if (-not $raw) { "No RebootTime given. Set the script variable RebootTime, e.g. 21:30 or 2026-10-05 21:30 (or cancel)."; exit 1 }

# Parse: HH:mm / 21h30, a date + time, or epoch seconds/milliseconds (NinjaOne date-time variables)
$now = Get-Date; $at = $null
if ($raw -match '^(\d{1,2})\s*[:hH]\s*(\d{2})$') {
    $at = $now.Date.AddHours([int]$matches[1]).AddMinutes([int]$matches[2])
    if ($at -le $now.AddMinutes(2)) { $at = $at.AddDays(1) }
} elseif ($raw -match '^\d{10,13}$') {
    $sec = if ($raw.Length -ge 13) { [int64]$raw / 1000 } else { [int64]$raw }
    $at = [DateTimeOffset]::FromUnixTimeSeconds([int64]$sec).LocalDateTime
} else {
    foreach ($c in [Globalization.CultureInfo]::InvariantCulture, [Globalization.CultureInfo]'fr-CA', [Globalization.CultureInfo]'en-US') {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse($raw, $c, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$d)) { $at = $d; break }
    }
}
if (-not $at) { "Could not read RebootTime '$raw'. Use 21:30 or 2026-10-05 21:30."; exit 1 }
if ($at -le $now.AddMinutes(2)) { "RebootTime $at is in the past. Nothing scheduled."; exit 1 }
if ($at -gt $now.AddDays(7)) { "RebootTime $at is more than 7 days away. Nothing scheduled."; exit 1 }

@'
param([string]$Target)
$Log = 'C:\ProgramData\ScheduledReboot\reboot.log'
function L($m) { "$(Get-Date -Format s)  $m" | Out-File $Log -Append -Encoding UTF8 }
$t = [datetime]$Target
L "Task fired (target $Target)."
if ((Get-Date) -gt $t.AddMinutes(90)) { L 'More than 90 min late (PC was asleep/off): reboot SKIPPED.'; Unregister-ScheduledTask -TaskName 'ScheduledReboot' -Confirm:$false -EA SilentlyContinue; return }
function Busy {
    $b = @()
    if (Get-Process -Name SetupHost, dism, sfc -EA SilentlyContinue) { $b += 'setup/dism/sfc running' }
    try { if ((New-Object -ComObject Microsoft.Update.Installer).IsBusy) { $b += 'Windows Update installing' } } catch { }
    $b -join ', '
}
$w0 = Get-Date
while (($why = Busy) -and ((Get-Date) - $w0).TotalMinutes -lt 60) { L "Waiting: $why"; Start-Sleep -Seconds 300 }
if ($why) { L "Still busy after 60 min ($why): rebooting anyway is risky -> reboot SKIPPED."; return }
$st = (Get-ItemProperty 'HKLM:\SYSTEM\Setup' -EA SilentlyContinue).SetupType
L "Rebooting in 2 min (SetupType=$st, CBS reboot pending=$(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'))."
Unregister-ScheduledTask -TaskName 'ScheduledReboot' -Confirm:$false -EA SilentlyContinue
& shutdown.exe /r /t 120 /d p:2:17 /c "Scheduled restart (Windows updates) in 2 minutes. Please save your work."
'@ | Set-Content $Job -Encoding UTF8

# Allow wake timers on AC power (Modern Standby PCs need this to wake for the task)
& powercfg.exe /setacvalueindex scheme_current sub_sleep bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d 1 | Out-Null
& powercfg.exe /setactive scheme_current | Out-Null

$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Job`" -Target `"$($at.ToString('s'))`""
$trg = New-ScheduledTaskTrigger -Once -At $at
$set = New-ScheduledTaskSettingsSet -WakeToRun -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName $Task -Action $act -Trigger $trg -Settings $set -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
"$(Get-Date -Format s)  Scheduled reboot for $($at.ToString('s'))" | Out-File (Join-Path $Base 'reboot.log') -Append -Encoding UTF8

$info = Get-ScheduledTaskInfo -TaskName $Task
"SCHEDULED: reboot at $($at.ToString('yyyy-MM-dd HH:mm')) (next run $($info.NextRunTime)). Wakes the PC from sleep; skipped if more than 90 min late."
$wt = (& powercfg.exe /waketimers) -join ' '
"Wake timer registered with Windows: $(if ($wt -match 'ScheduledReboot') { 'YES' } else { 'not listed by powercfg /waketimers (check reboot.log after the reboot time)' })"
