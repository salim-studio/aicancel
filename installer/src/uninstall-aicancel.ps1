<#
.SYNOPSIS
  Uninstalls aicancel (files, shortcuts, watchdog, ARP entry).
  Does NOT re-enable Windows AI — run aicancel.ps1 -Revert first if wanted.
.NOTES
  Copyright (c) 2026 salim-slimani. Licensed under the MIT License.
#>
#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$dest = Split-Path -Parent $PSCommandPath
Write-Host 'Uninstalling aicancel...' -ForegroundColor Cyan

# 1) watchdog task
Unregister-ScheduledTask -TaskName 'aicancel-watchdog' -Confirm:$false

# 2) shortcuts
$sm = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\aicancel.lnk"
$dt = "$env:PUBLIC\Desktop\aicancel.lnk"
Remove-Item $sm -Force
Remove-Item $dt -Force

# 3) install directory (this script runs from inside it — copy to TEMP first)
$me = $PSCommandPath
$tmp = "$env:TEMP\aicancel-uninstall-final.ps1"
$final = @'
$ErrorActionPreference = 'SilentlyContinue'
Start-Sleep -Seconds 2
Remove-Item -LiteralPath '__DEST__' -Recurse -Force
reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\aicancel" /f | Out-Null
Write-Host 'aicancel uninstalled.' -ForegroundColor Green
Remove-Item -LiteralPath $PSCommandPath -Force
'@ -replace '__DEST__', $dest
$final | Out-File $tmp -Encoding utf8 -Force
Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`""

# 4) ARP entry
reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\aicancel' /f | Out-Null
Write-Host 'aicancel uninstalled.' -ForegroundColor Green
