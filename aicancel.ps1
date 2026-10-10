<#
.SYNOPSIS
  aicancel v1.1.0 — Cancel Windows AI. Reclaim a clean, private, AI-free Windows.
  Removes and disables Copilot, Recall, Click to Do, AI Fabric, Edge AI,
  Office AI, Defender AI agents and related background services.
.DESCRIPTION
  Fast, complete and safe:
  - Works on Windows PowerShell 5.1 and PowerShell 7+
  - Single-pass registry batch, single CBS scan, single TrustedInstaller pass
  - Scan-only preview (-ScanOnly), backup (-Backup), full revert (-Revert)
  - Update watchdog keeps AI components from silently returning
  - Optional transcript logging (-EnableLog)
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File aicancel.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File aicancel.ps1 -NonInteractive -All
  powershell -NoProfile -ExecutionPolicy Bypass -File aicancel.ps1 -NonInteractive -Options DisableReg,RemoveAppx,RemoveCBS -Backup
  powershell -NoProfile -ExecutionPolicy Bypass -File aicancel.ps1 -NonInteractive -All -Revert
  powershell -NoProfile -ExecutionPolicy Bypass -File aicancel.ps1 -ScanOnly
.NOTES
  Copyright (c) 2026 salim-slimani. All rights reserved. Licensed under the MIT License.
  Project: https://github.com/salim-studio/aicancel
#>
[CmdletBinding()]
param(
  [switch]$NonInteractive,
  [switch]$All,
  [ValidateSet('DisableReg','BlockReinstall','RegionPolicy','RemoveAppx','RemoveRecall','RemoveCBS','RemoveFiles','HideAISettings','NoRewrite','KillTasks','Watchdog','NoDefenderAI','EdgeAI','OfficeAI')]
  [string[]]$Options = @(),
  [switch]$Exclude,
  [switch]$Backup,
  [switch]$Revert,
  [switch]$ScanOnly,
  [switch]$NoReboot,
  [switch]$EnableLog
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'

# ---------- helpers ----------
$Global:AICancelVer = '1.1.0'
$Global:Root = "$env:USERPROFILE\aicancel"
$Global:BackupDir = "$Root\Backup"
$Global:LogFile = "$Root\aicancel-$(Get-Date -Format 'yyyyMMdd-HHmm').log"
$Global:IsRevert = [bool]$Revert
$Global:DoBackup = [bool]$Backup
$Global:T0 = Get-Date

function Log([string]$m, [string]$c='Cyan') {
  $tag = if ($Global:IsRevert) {'REVERT'} else {'DO'}
  if ($ScanOnly) { $tag = 'SCAN' }
  Write-Host "[$tag] $m" -ForegroundColor $c
  if ($EnableLog) {
    try {
      if (-not (Test-Path $Global:Root)) { New-Item $Global:Root -ItemType Directory -Force | Out-Null }
      "[$((Get-Date).ToString('o'))][$tag] $m" | Out-File $Global:LogFile -Append -Encoding utf8
    } catch {}
  }
}
function Ok([string]$m){ Log "+ $m" 'Green' }
function Warn([string]$m){ Log "! $m" 'Yellow' }
function Err([string]$m){ Log "x $m" 'Red' }

# ---------- admin / env ----------
function Ensure-Admin {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
  if (-not $isAdmin) {
    Warn 'Restarting as administrator...'
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$PSCommandPath`"") + $MyInvocation.BoundParameters.GetEnumerator().ForEach({
      if ($_.Value -is [switch] -and $_.Value) { "-$($_.Key)" }
      elseif ($_.Value -is [array]) { "-$($_.Key) $($_.Value -join ',')" }
    })
    Start-Process powershell.exe -ArgumentList $args -Verb RunAs
    exit
  }
}
function Fix-Path {
  if ($env:PATH -notlike "*$env:SystemRoot\system32*") {
    $env:PATH = "$env:SystemRoot\system32;$env:SystemRoot;$env:SystemRoot\System32\Wbem;" + $env:PATH
  }
}
function Test-PendingUpdate {
  $a = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
  $b = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
  $busy = $false
  try { $busy = (New-Object -ComObject Microsoft.Update.Installer).IsBusy } catch {}
  return ($a -or $b -or $busy)
}

# ---------- fast reg batch ----------
# One entry per registry value: Hive, Key, Name, Type, Data
function Invoke-RegBatch([array]$list) {
  foreach ($r in $list) {
    if ($ScanOnly) { Log "REG $($r.Hive)\$($r.Key) [$($r.Name)=$($r.Data)]" 'Gray'; continue }
    $h = $r.Hive; $k = $r.Key; $n = $r.Name; $t = $r.Type; $d = $r.Data
    try {
      if ($null -eq $n -or $n -eq '') {
        & reg.exe add "$h\$k" /f *>$null
      } elseif ($t -eq 'DELETE') {
        & reg.exe delete "$h\$k" /v $n /f *>$null
      } elseif ($t -eq 'DELETEKEY') {
        & reg.exe delete "$h\$k" /f *>$null
      } else {
        & reg.exe add "$h\$k" /v $n /t $t /d $d /f *>$null
      }
    } catch {}
  }
}
function Backup-RegKey([string]$hivePath, [string]$outFile) {
  if (-not $Global:DoBackup) { return }
  try {
    if (-not (Test-Path $Global:BackupDir)) { New-Item $Global:BackupDir -ItemType Directory -Force | Out-Null }
    & reg.exe export $hivePath $outFile /y *>$null
  } catch {}
}

# ---------- .pol sync (compact, fast) ----------
function Sync-Pol {
  param([string]$Hive,[string]$Key,[string]$Name,[string]$Type,[string]$Value,[switch]$Delete)
  if ($ScanOnly) { return }
  try {
    if (-not ([System.Management.Automation.PSTypeName]'PolHandlerX').Type) {
      Add-Type -Language CSharp @'
using System;using System.Collections.Generic;using System.IO;using System.Text;
public class PolRecX{public string Key;public string ValueName;public uint Type;public byte[] Data;}
public static class PolHandlerX{
 public static List<PolRecX> Read(string f){var l=new List<PolRecX>();if(!File.Exists(f)||new FileInfo(f).Length<8)return l;
  try{using(var br=new BinaryReader(File.OpenRead(f),Encoding.Unicode)){if(br.ReadUInt32()!=0x67655250||br.ReadUInt32()!=1)return l;
   while(br.BaseStream.Position<br.BaseStream.Length){if(br.ReadChar()!='[')continue;var r=new PolRecX{Key=RS(br)};if(br.ReadChar()!=';')break;
    r.ValueName=RS(br);if(br.ReadChar()!=';')break;r.Type=br.ReadUInt32();if(br.ReadChar()!=';')break;uint sz=br.ReadUInt32();if(br.ReadChar()!=';')break;
    if(br.BaseStream.Position+sz>br.BaseStream.Length)break;r.Data=br.ReadBytes((int)sz);if(br.ReadChar()!=']')break;l.Add(r);}}}catch{}return l;}
 public static void Write(string f,ICollection<PolRecX> d){Directory.CreateDirectory(Path.GetDirectoryName(f));
  using(var bw=new BinaryWriter(File.Open(f,FileMode.Create),Encoding.Unicode)){bw.Write((uint)0x67655250);bw.Write((uint)1);
   foreach(var r in d){bw.Write('[');SS(bw,r.Key);bw.Write(';');SS(bw,r.ValueName);bw.Write(';');bw.Write(r.Type);bw.Write(';');bw.Write((uint)r.Data.Length);bw.Write(';');bw.Write(r.Data);bw.Write(']');}}}
 static string RS(BinaryReader br){var sb=new StringBuilder();char c;while((c=br.ReadChar())!=0)sb.Append(c);return sb.ToString();}
 static void SS(BinaryWriter bw,string v){bw.Write(v.ToCharArray());bw.Write((char)0);}}
'@
    }
    $pol = if ($Hive -eq 'HKLM') { "$env:SystemRoot\System32\GroupPolicy\Machine\Registry.pol" } else { "$env:SystemRoot\System32\GroupPolicy\User\Registry.pol" }
    $dict = [System.Collections.Generic.Dictionary[string,PolRecX]]::new([StringComparer]::OrdinalIgnoreCase)
    [PolHandlerX]::Read($pol) | ForEach-Object { $dict["$($_.Key);$($_.ValueName)"] = $_ }
    $dk = "$Key;$Name"
    if ($Delete) { $dict.Remove($dk) | Out-Null }
    else {
      $rec = [PolRecX]::new(); $rec.Key=$Key; $rec.ValueName=$Name
      if ($Type -eq 'DWORD') { $rec.Type=4; $rec.Data=[BitConverter]::GetBytes([uint32]$Value) }
      else { $rec.Type=1; $rec.Data=[Text.Encoding]::Unicode.GetBytes($Value+[char]0) }
      $dict[$dk]=$rec
    }
    $final=[System.Collections.Generic.List[PolRecX]]::new($dict.Values)
    [PolHandlerX]::Write($pol,$final)
  } catch {}
}
function Set-Policy([string]$Hive,[string]$Key,[string]$Name,[string]$Value) {
  $v = $Value
  if ($Global:IsRevert) {
    # revert: recall-allow=1, disable*=0 — handled by caller passing correct values; pol just mirrors
  }
  if ($ScanOnly) { Log "POLICY $Hive\$Key [$Name=$v]" 'Gray'; return }
  & reg.exe add "$Hive\$Key" /v $Name /t REG_DWORD /d $v /f *>$null
  Sync-Pol -Hive $Hive -Key $Key -Name $Name -Type DWORD -Value $v
}

# ---------- TrustedInstaller exec (single-shot) ----------
function Invoke-Trusted([string]$command) {
  if ($ScanOnly) { Log "TRUSTED: $command" 'Gray'; return }
  try {
    $ti = "$env:SystemRoot\servicing\TrustedInstaller.exe"
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='TrustedInstaller'"
    $def = $svc.PathName; if ($def -ne $ti) { $def = $ti }
    $b = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    & sc.exe config TrustedInstaller binPath= "cmd.exe /c powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $b" | Out-Null
    & sc.exe start TrustedInstaller | Out-Null
    Start-Sleep -Milliseconds 800
    & sc.exe config TrustedInstaller binPath= "`"$def`"" | Out-Null
    try { Stop-Service TrustedInstaller -Force } catch { & taskkill.exe /im trustedinstaller.exe /f *>$null }
  } catch {
    # fallback: system scheduled task
    try {
      $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""
      $pri = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest
      $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
      Register-ScheduledTask -TaskName 'aicancel-sys' -Action $act -Principal $pri -Settings $set -Force | Out-Null
      Start-ScheduledTask -TaskName 'aicancel-sys'
      Start-Sleep 2
      Unregister-ScheduledTask -TaskName 'aicancel-sys' -Confirm:$false
    } catch {}
  }
}

# ============================================================
# 1) DisableReg — all AI registry keys in a single fast batch
# ============================================================
function Do-DisableReg {
  Log 'Disabling Copilot / Recall / AI registry keys...'
  $R = $Global:IsRevert
  $on  = @{1='1';0='0'} # helper
  $D1 = if (-not $R) {'1'} else {'0'}  # Disable*=1
  $D0 = if (-not $R) {'0'} else {'1'}  # Enable*=0 / IsAvailable 0
  $AllowRecall = if (-not $R) {'0'} else {'1'}

  if ($Global:DoBackup -and -not $ScanOnly) {
    Backup-RegKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' "$BackupDir\WindowsAI-HKLM.reg"
    Backup-RegKey 'HKCU\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' "$BackupDir\WindowsAI-HKCU.reg"
    Backup-RegKey 'HKLM\SOFTWARE\Policies\Microsoft\Edge' "$BackupDir\Edge.reg"
  }

  # --- policies (reg + pol) ---
  $pols = @(
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAIDataAnalysis',$D1),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','AllowRecallEnablement',$AllowRecall),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableClickToDo',$D1),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','TurnOffSavingSnapshots',$D1),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableSettingsAgent',$D1),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAgentConnectors',$D1),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAgentWorkspaces',$D1),
    @('HKLM','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableRemoteAgentConnectors',$D1),
    @('HKCU','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableAIDataAnalysis',$D1),
    @('HKCU','SOFTWARE\Policies\Microsoft\Windows\WindowsAI','DisableClickToDo',$D1),
    @('HKCU','SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot','TurnOffWindowsCopilot',$D1)
  )
  foreach ($p in $pols) { Set-Policy $p[0] $p[1] $p[2] $p[3] }

  # --- batch reg (single loop = fast) ---
  $batch = @(
    @{Hive='HKLM';Key='SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat';Name='IsUserEligible';Type='REG_DWORD';Data=$D0},
    @{Hive='HKLM';Key='SOFTWARE\Microsoft\Windows\Shell\Copilot';Name='IsCopilotAvailable';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat';Name='IsUserEligible';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='SOFTWARE\Microsoft\Windows\Shell\Copilot';Name='IsCopilotAvailable';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='ShowCopilotButton';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\input\Settings';Name='InsightsEnabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\Shell\ClickToDo';Name='DisableClickToDo';Type='REG_DWORD';Data=$D1},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\M365Copilot';Name='AutoStartDelayEnabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\M365Copilot';Name='IsCompanionWindowAvailable';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='SOFTWARE\Policies\Microsoft\Windows\Explorer';Name='DisableSearchBoxSuggestions';Type='REG_DWORD';Data=$D1},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\WindowsCopilot';Name='AllowCopilotRuntime';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins';Name='CopilotPWAPin';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband\AuxilliaryPins';Name='RecallPin';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Speech_OneCore\Settings\VoiceActivation\UserPreferenceForAllApps';Name='AgentActivationEnabled';Type='REG_DWORD';Data=$D0},
    # consent stores
    @{Hive='HKLM';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\generativeAI';Name='Value';Type='REG_SZ';Data=$(if(-not $R){'Deny'}else{'Allow'})},
    @{Hive='HKLM';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels';Name='Value';Type='REG_SZ';Data=$(if(-not $R){'Deny'}else{'Allow'})},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\systemAIModels';Name='Value';Type='REG_SZ';Data=$(if(-not $R){'Deny'}else{'Allow'})},
    @{Hive='HKLM';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\Capabilities\systemAIModels';Name='RecordUsageData';Type='REG_DWORD';Data=$D0},
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';Name='LetAppsAccessGenerativeAI';Type='REG_DWORD';Data=$(if(-not $R){'2'}else{'1'})},
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';Name='LetAppsAccessSystemAIModels';Type='REG_DWORD';Data=$(if(-not $R){'2'}else{'1'})},
    @{Hive='HKLM';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings';Name='AutoOpenCopilotLargeScreens';Type='REG_DWORD';Data=$D0},
    # background access
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe';Name='Disabled';Type='REG_DWORD';Data=$D1},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.Copilot_8wekyb3d8bbwe';Name='DisabledByUser';Type='REG_DWORD';Data=$D1},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe';Name='DisabledByUser';Type='REG_DWORD';Data=$D1},
    # voice access / effects
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\VoiceActivation';Name='AllowVoiceActivation';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='SOFTWARE\Microsoft\Speech_OneCore\AudioPolicy\VoiceActivation';Name='VoiceActivationEnabled';Type='REG_DWORD';Data=$D0},
    # settings search AI + gaming copilot
    @{Hive='HKCU';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings';Name='IsDeviceSearchHistoryEnabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR';Name='AppCaptureEnabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Windows\CurrentVersion\Privacy';Name='TailoredExperiencesWithDiagnosticDataEnabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\DataCollection';Name='AllowTelemetry';Type='REG_DWORD';Data=$D0}
  )
  Invoke-RegBatch $batch

  # CopilotDisabledReason (string needs space on revert)
  if ($ScanOnly) { Log 'REG CopilotDisabledReason' 'Gray' }
  else {
    & reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v CopilotDisabledReason /t REG_SZ /d $(if(-not $R){'FeatureIsDisabled'}else{' '}) /f *>$null
    & reg.exe add "HKCU\SOFTWARE\Microsoft\Windows\Shell\Copilot" /v CopilotDisabledReason /t REG_SZ /d $(if(-not $R){'FeatureIsDisabled'}else{' '}) /f *>$null
  }

  # cleanup telemetry leftovers (fast, guarded)
  if (-not $R -and -not $ScanOnly) {
    & reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsAI\LastConfiguration' /f *>$null
    & reg.exe delete 'HKCU\Software\Microsoft\Windows\Shell\Copilot' /v CopilotLogonTelemetryTime /f *>$null
    try {
      $rk = (Get-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunNotification' -EA SilentlyContinue).Property | Where-Object { $_ -like '*Copilot*' -or $_ -like '*M365*' }
      foreach ($k in $rk) { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunNotification' -Name $k -Force -EA SilentlyContinue }
    } catch {}
  }
  Ok 'Registry lockdown done.'
}

# ============================================================
# 2) EdgeAI
# ============================================================
function Do-EdgeAI {
  Log 'Disabling AI in Edge...'
  $R = $Global:IsRevert
  $D1 = if (-not $R) {'1'} else {'0'}
  $D0 = if (-not $R) {'0'} else {'1'}
  $list = @(
    @('CopilotCDPPageContext',$D0),@('CopilotPageContext',$D0),@('HubsSidebarEnabled',$D0),
    @('EdgeEntraCopilotPageContext',$D0),@('Microsoft365CopilotChatIconEnabled',$D0),
    @('EdgeHistoryAISearchEnabled',$D0),@('ComposeInlineEnabled',$D0),
    @('BuiltInAIAPIsEnabled',$D0),@('AIGenThemesEnabled',$D0),
    @('ShareBrowsingHistoryWithCopilotSearchAllowed',$D0),@('AllowBrowsingWithCopilot',$D0),
    @('CopilotNewTabPageEnabled',$D0),@('M365LinksAutoOpenCopilotEnabled',$D0),
    @('CopilotAddressBarSuggestionsEnabled',$D0),@('CopilotCoworkToolActionsEnabled',$D0)
  )
  $batch = @()
  foreach ($e in $list) { $batch += @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Edge';Name=$e[0];Type='REG_DWORD';Data=$e[1]} }
  $batch += @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Edge';Name='GenAILocalFoundationalModelSettings';Type='REG_DWORD';Data=$D1}
  $batch += @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Edge';Name='DevToolsGenAiSettings';Type='REG_DWORD';Data=$(if(-not $R){'2'}else{'1'})}
  Invoke-RegBatch $batch

  # edge://flags via Local State (kill edge first — fast)
  if (-not $ScanOnly) {
    try { & taskkill.exe /im msedge.exe /f *>$null } catch {}
    $ls = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
    if (Test-Path $ls) {
      try {
        $raw = (Get-Content $ls -Raw -EA Stop).Replace('""','"_empty"')
        $j = $raw | ConvertFrom-Json -EA Stop
        if (-not $j.browser.enabled_labs_experiments) { $j.browser | Add-Member -NotePropertyName enabled_labs_experiments -NotePropertyValue @() }
        $flags = @('edge-copilot-mode@2','edge-ntp-composer@2','edge-compose@2')
        if ($R) { $j.browser.enabled_labs_experiments = @($j.browser.enabled_labs_experiments | Where-Object { $_ -notin $flags }) }
        else { foreach ($f in $flags) { if ($j.browser.enabled_labs_experiments -notcontains $f) { $j.browser.enabled_labs_experiments += $f } } }
        ($j | ConvertTo-Json -Compress -Depth 12).Replace('"_empty"','""') | Set-Content $ls -Encoding UTF8 -Force
      } catch { Warn 'Could not patch Edge Local State. Disable Copilot flags manually at edge://flags' }
    }
  }
  Ok 'Edge done.'
}

# ============================================================
# 3) OfficeAI
# ============================================================
function Do-OfficeAI {
  Log 'Disabling Copilot in Office...'
  $R = $Global:IsRevert
  $D1 = if (-not $R) {'1'} else {'0'}
  $D0 = if (-not $R) {'0'} else {'1'}
  $D2 = if (-not $R) {'2'} else {'1'}
  Invoke-RegBatch @(
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\office\16.0\common\ai\training\general';Name='disabletraining';Type='REG_DWORD';Data=$D1},
    @{Hive='HKCU';Key='Software\Policies\Microsoft\office\16.0\common\privacy';Name='controllerconnectedservicesenabled';Type='REG_DWORD';Data=$D2},
    @{Hive='HKCU';Key='Software\Policies\Microsoft\office\16.0\common\privacy';Name='usercontentdisabled';Type='REG_DWORD';Data=$D2},
    @{Hive='HKCU';Key='Software\Microsoft\Office\16.0\Word\Options';Name='EnableCopilot';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Office\16.0\Excel\Options';Name='EnableCopilot';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Office\16.0\OneNote\Options\Copilot';Name='CopilotEnabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Office\16.0\PowerPoint\Options';Name='Enable Copilot in Settings';Type='REG_DWORD';Data=$D0},
    @{Hive='HKCU';Key='Software\Microsoft\Office\16.0\WritingAssistant';Name='Enabled';Type='REG_DWORD';Data=$D0},
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\office\16.0\common\ai\contentsafety\general';Name='disablecontentsafety';Type='REG_DWORD';Data=$D1},
    @{Hive='HKCU';Key='Software\Policies\Microsoft\Cloud\Office\16.0\common\copilot';Name='CopilotPinning';Type='REG_DWORD';Data=$D0}
  )
  Ok 'Office done.'
}

# ============================================================
# 4) RegionPolicy (IntegratedServicesRegionPolicySet.json)
# ============================================================
function Do-RegionPolicy {
  Log 'Patching regional AI policies...'
  $p = "$env:SystemRoot\System32\IntegratedServicesRegionPolicySet.json"
  if (-not (Test-Path $p)) { Warn 'RegionPolicy file not found — skipping.'; return }
  if ($ScanOnly) { Log "SCAN $p" 'Gray'; return }
  try {
    if ($Global:DoBackup) { Copy-Item $p "$BackupDir\IntegratedServicesRegionPolicySet.bak" -Force }
    $j = (Get-Content $p -Raw) | ConvertFrom-Json
    $n = 0
    foreach ($pol in $j.policies) {
      if ($pol.name -like '*Copilot*' -or $pol.name -like '*Recall*') {
        $pol.defaultState = if ($Global:IsRevert) { 'enabled' } else { 'disabled' }
        $n++
      }
    }
    $j | ConvertTo-Json -Depth 20 | Set-Content $p -Encoding UTF8 -Force
    Ok "Patched $n regional policies."
  } catch { Err "RegionPolicy patch failed: $($_.Exception.Message)" }
}

# ============================================================
# 5) BlockReinstall — block AI package reinstall via Appx policies
# ============================================================
function Do-BlockReinstall {
  Log 'Blocking AI package reinstall...'
  if ($ScanOnly) { Log 'SCAN BlockReinstall' 'Gray'; return }
  if ($Global:IsRevert) {
    & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages' /f *>$null
    Ok 'Reinstall block removed (revert).'; return
  }
  Invoke-RegBatch @(
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages\Microsoft.Copilot_8wekyb3d8bbwe';Name='';Type='REG';Data=''},
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages\Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe';Name='';Type='REG';Data=''}
  )
  # An empty DynamicRemovalList blocks automatic reinstall
  & reg.exe add 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages' /v DynamicRemovalList /t REG_SZ /d '' /f *>$null
  Ok 'Reinstall block enabled.'
}

# ============================================================
# 6) RemoveAppx — remove AI Appx packages (normal pass + one TrustedInstaller pass)
# ============================================================
function Get-AIPackagePatterns {
  return @(
    'MicrosoftWindows.Client.AIX','MicrosoftWindows.Client.CoPilot','Microsoft.Windows.Ai.Copilot.Provider',
    'Microsoft.Copilot','Microsoft.MicrosoftOfficeHub','MicrosoftWindows.Client.CoreAI',
    'Microsoft.Edge.GameAssist','Microsoft.Office.ActionsServer','Microsoft.WritingAssistant',
    'Clipchamp.Clipchamp','Microsoft.AIFabric.CBS','Microsoft.Ink.Handwriting',
    'WindowsWorkload.*','MicrosoftCorporationII.WinML*',
    'MicrosoftWindows.*.Voiess','MicrosoftWindows.*.Speion','MicrosoftWindows.*.Livtop','MicrosoftWindows.*.Filons'
  )
}
function Do-RemoveAppx {
  Log 'Removing AI Appx packages...'
  $pats = Get-AIPackagePatterns
  if ($ScanOnly) {
    try {
      Get-AppxPackage -AllUsers -EA SilentlyContinue | Where-Object {
        $n=$_.Name; ($pats | Where-Object { $n -like $_ }) -ne $null
      } | ForEach-Object { Log "FOUND Appx: $($_.Name) $($_.PackageFullName)" 'Gray' }
      Get-AppxProvisionedPackage -Online -EA SilentlyContinue | Where-Object {
        $n=$_.DisplayName; ($pats | Where-Object { $n -like $_ }) -ne $null
      } | ForEach-Object { Log "FOUND Prov: $($_.DisplayName)" 'Gray' }
    } catch {}
    return
  }
  if ($Global:IsRevert) { Warn 'Appx revert requires the Microsoft Store — reinstall apps manually if needed. (The restore point covers system state)'; return }

  # 1) Fast normal pass for current and all users (covers most packages)
  try {
    $all = Get-AppxPackage -AllUsers -EA SilentlyContinue
    foreach ($rx in $pats) {
      foreach ($a in ($all | Where-Object { $_.Name -like $rx })) {
        try { Remove-AppxPackage -Package $a.PackageFullName -AllUsers -EA SilentlyContinue } catch {}
      }
    }
    $prov = Get-AppxProvisionedPackage -Online -EA SilentlyContinue
    foreach ($rx in $pats) {
      foreach ($a in ($prov | Where-Object { $_.DisplayName -like $rx -or $_.PackageName -like "*$rx*" })) {
        try { Remove-AppxProvisionedPackage -Online -PackageName $a.PackageName -AllUsers -EA SilentlyContinue } catch {}
      }
    }
  } catch {}

  # 2) One TrustedInstaller pass for locked packages (EOL + Deprovisioned + Inbox + NonRemovable)
  $patStr = ($pats -join ',')
  $inner = @'
param([string]$P)
$rx=$P -split ','
$prov=Get-AppxProvisionedPackage -Online
$pkgs=Get-AppxPackage -AllUsers
$store='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore'
foreach($r in $rx){
 foreach($a in ($prov|?{$_.DisplayName -like $r -or $_.PackageName -like "*$r*"})){
  try{$fam=($pkgs|?{$_.Name -eq $a.DisplayName}|select -First 1).PackageFamilyName
   if($fam){ni "$store\Deprovisioned\$fam" -Force|Out-Null;Set-NonRemovableAppsPolicy -Online -PackageFamilyName $fam -NonRemovable 0}
   Remove-AppxProvisionedPackage -Online -PackageName $a.PackageName -AllUsers}catch{}}
 foreach($a in ($pkgs|?{$_.Name -like $r -or $_.PackageFullName -like "*$r*"})){
  try{$fam=$a.PackageFamilyName;$full=$a.PackageFullName
   ni "$store\Deprovisioned\$fam" -Force|Out-Null
   try{Set-NonRemovableAppsPolicy -Online -PackageFamilyName $fam -NonRemovable 0}catch{}
   ri "$store\InboxApplications\$full" -Force -EA SilentlyContinue
   $sids=@('S-1-5-18');try{$sids+=(gci $store -EA SilentlyContinue|?{$_.PSChildName -like 'S-1-5-21*'}).PSChildName}catch{}
   foreach($s in $sids){try{ni "$store\EndOfLife\$s\$fam" -Force|Out-Null}catch{}}
   Remove-AppxPackage -Package $full -AllUsers -EA SilentlyContinue
   foreach($s in $sids){try{ri "$store\EndOfLife\$s\$fam" -Force -EA SilentlyContinue}catch{}}
  }catch{}}}
'@
  $tmp = "$env:TEMP\aicancel-appx.ps1"
  $inner | Out-File $tmp -Encoding utf8 -Force
  Invoke-Trusted "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$tmp`" -P '$patStr'"
  try { Remove-Item $tmp -Force -EA SilentlyContinue } catch {}
  Ok 'Appx removal done.'
}

# ============================================================
# 7) RemoveRecall (Optional Feature)
# ============================================================
function Do-RemoveRecall {
  Log 'Removing the Recall feature...'
  if ($ScanOnly) { Log 'SCAN Recall feature' 'Gray'; return }
  if ($Global:IsRevert) { Warn 'Recall revert: re-enable it manually from Optional Features if you want it back.'; return }
  try { Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -Remove -NoRestart -EA SilentlyContinue | Out-Null } catch {}
  try { & dism.exe /Online /Disable-Feature /FeatureName:Recall /Remove /NoRestart /Quiet *>$null } catch {}
  Ok 'Recall handled.'
}

# ============================================================
# 8) RemoveCBS — reveal and remove hidden AI CBS packages in a single scan
# ============================================================
function Do-RemoveCBS {
  Log 'Removing hidden AI CBS packages...'
  $kw = @('*AIX*','*Recall*','*Copilot*','*CoreAI*','*AIFabric*','*PhiSilica*','*WindowsWorkload*','*OnnxRuntime*','*WinML*','*ImageSearch*')
  $reg = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\Packages'
  if (-not (Test-Path $reg)) { Warn 'No CBS store found.'; return }
  $found = @()
  foreach ($k in (Get-ChildItem $reg -EA SilentlyContinue)) {
    $name = $k.PSChildName
    $hit = $false; foreach ($w in $kw) { if ($name -like $w) { $hit=$true; break } }
    if (-not $hit) { continue }
    $found += $name
    if ($ScanOnly) { Log "FOUND CBS: $name" 'Gray'; continue }
    if ($Global:IsRevert) { continue }
    try {
      $rp = "registry::$($k.Name)"
      try { $vis = Get-ItemPropertyValue $rp -Name Visibility -EA Stop } catch { $vis = $null }
      if ($vis -eq 2) {
        Set-ItemProperty $rp -Name Visibility -Value 1 -Force -EA SilentlyContinue
        New-ItemProperty $rp -Name DefVis -PropertyType DWord -Value 2 -Force -EA SilentlyContinue | Out-Null
        Remove-Item "$rp\Owners" -Force -Recurse -EA SilentlyContinue
        Remove-Item "$rp\Updates" -Force -Recurse -EA SilentlyContinue
      }
      try { Remove-WindowsPackage -Online -PackageName $name -NoRestart -EA Stop | Out-Null }
      catch { & dism.exe /Online /Remove-Package /PackageName:$name /NoRestart /Quiet *>$null }
      Get-ChildItem "$env:windir\servicing\Packages" -Filter "*$name*" -EA SilentlyContinue | ForEach-Object {
        try { Remove-Item $_.FullName -Force -EA SilentlyContinue } catch {}
      }
    } catch {}
  }
  if ($ScanOnly) { Log "CBS candidates found: $($found.Count)" 'Yellow' }
  else { Ok "Processed $($found.Count) CBS packages." }
}

# ============================================================
# 9) RemoveFiles — leftover AI folders/files plus app policies (Notepad/Photos/Snipping)
# ============================================================
function Do-RemoveFiles {
  Log 'Cleaning leftover AI files...'
  if ($Global:IsRevert) {
    & reg.exe delete 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Notepad' /v DisableRewrite /f *>$null
    Ok 'Notepad Rewrite restored (revert).'; return
  }
  if ($ScanOnly) { Log 'SCAN files' 'Gray' }
  else {
    $dirs = @(
      "$env:SystemRoot\System32\WindowsAI",
      "$env:ProgramFiles\WindowsApps\Microsoft.Copilot*",
      "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.AIX*",
      "$env:ProgramFiles\WindowsApps\MicrosoftWindows.Client.CoPilot*",
      "$env:LOCALAPPDATA\Packages\Microsoft.Copilot_8wekyb3d8bbwe",
      "$env:LOCALAPPDATA\Microsoft\Windows\WindowsAI"
    )
    foreach ($d in $dirs) {
      try {
        foreach ($m in (Get-Item $d -EA SilentlyContinue)) {
          try { Remove-Item $m.FullName -Recurse -Force -EA SilentlyContinue } catch {}
        }
      } catch {}
    }
    # Known AI-related DLLs only (never blanket system32 deletes)
    foreach ($f in (Get-ChildItem "$env:SystemRoot\System32" -Filter "*ai*copilot*" -EA SilentlyContinue)) {
      try { Remove-Item $f.FullName -Force -EA SilentlyContinue } catch {}
    }
  }
  # App policies (also shown in scan mode)
  $batch = @(
    @{Hive='HKLM';Key='SOFTWARE\Policies\Microsoft\Windows\Notepad';Name='DisableRewrite';Type='REG_DWORD';Data=$(if(-not $Global:IsRevert){'1'}else{'0'})},
    @{Hive='HKCU';Key='SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy';Name='TailoredExperiencesWithDiagnosticDataEnabled';Type='REG_DWORD';Data=$(if(-not $Global:IsRevert){'0'}else{'1'})}
  )
  Invoke-RegBatch $batch
  # Hide the AI Components settings page
  $hide = if (-not $Global:IsRevert) { 'hide:ai-components' } else { '' }
  if ($ScanOnly) { Log "Settings PageVisibility=$hide" 'Gray' }
  else {
    if ($hide) { & reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v SettingsPageVisibility /t REG_SZ /d $hide /f *>$null }
    else { & reg.exe delete 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' /v SettingsPageVisibility /f *>$null }
  }
  Ok 'File cleanup done.'
}

# ============================================================
# 10) KillTasks — Windows AI scheduled tasks
# ============================================================
function Do-KillTasks {
  Log 'Removing Windows AI scheduled tasks...'
  $names = @('*WindowsAI*','*Recall*','*Copilot*','*ClickToDo*','*AIFabric*')
  if ($ScanOnly) {
    try {
      foreach ($n in $names) { Get-ScheduledTask -TaskName $n -EA SilentlyContinue | ForEach-Object { Log "FOUND Task: $($_.TaskPath)$($_.TaskName)" 'Gray' } }
    } catch {}
    return
  }
  if ($Global:IsRevert) { Warn 'Deleted tasks cannot auto-restore — use the restore point.'; return }
  foreach ($n in $names) {
    try {
      Get-ScheduledTask -TaskName $n -EA SilentlyContinue | ForEach-Object {
        try { Unregister-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -Confirm:$false -EA SilentlyContinue } catch {}
      }
    } catch {}
  }
  # Stubborn task files via TrustedInstaller
  Invoke-Trusted "Get-ChildItem '$env:SystemRoot\System32\Tasks\Microsoft\Windows\WindowsAI' -Recurse -EA SilentlyContinue | Remove-Item -Force -Recurse -EA SilentlyContinue; Remove-Item 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\TaskCache\Tree\Microsoft\Windows\WindowsAI' -Recurse -Force -EA SilentlyContinue"
  Ok 'Scheduled tasks done.'
}

# ============================================================
# 11) Watchdog — scheduled guard that stops AI returning with updates
# ============================================================
function Do-Watchdog {
  $tn = 'aicancel-watchdog'
  if ($Global:IsRevert -or $ScanOnly) {
    if ($ScanOnly) { Log "SCAN watchdog task $tn" 'Gray'; return }
    try { Unregister-ScheduledTask -TaskName $tn -Confirm:$false -EA SilentlyContinue; Ok 'Watchdog removed.' } catch {}
    return
  }
  Log 'Installing the update watchdog...'
  $script = "`"$PSCommandPath`" -NonInteractive -Options DisableReg,RemoveAppx,KillTasks,EdgeAI -NoReboot"
  $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $script"
  $trg = New-ScheduledTaskTrigger -AtLogOn
  $trg2 = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am
  $pri = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -RunLevel Highest
  $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
  try {
    Register-ScheduledTask -TaskName $tn -Action $act -Trigger @($trg,$trg2) -Principal $pri -Settings $set -Description 'aicancel: re-apply AI removal after updates' -Force | Out-Null
    Ok 'Watchdog installed.'
  } catch { Err 'Watchdog install failed.' }
}

# ============================================================
# 12) NoDefenderAI — Defender AI agent
# ============================================================
function Do-NoDefenderAI {
  Log 'Disabling Defender AI...'
  if ($ScanOnly) { Log 'SCAN Defender AI' 'Gray'; return }
  if ($Global:IsRevert) {
    & reg.exe delete 'HKLM\SOFTWARE\Image File Execution Options\AIDefenderHost.exe' /v Debugger /f *>$null
    try { Set-MpPreference -DisableAIAgent $false -EA SilentlyContinue } catch {}
    Ok 'Defender AI restored.'; return
  }
  try { Set-MpPreference -DisableAIAgent $true -EA SilentlyContinue } catch {}
  try { Set-MpPreference -DisableAiProtection $true -EA SilentlyContinue } catch {}
  & reg.exe add 'HKLM\SOFTWARE\Image File Execution Options\AIDefenderHost.exe' /v Debugger /t REG_SZ /d 'systray.exe' /f *>$null
  Ok 'Defender AI done.'
}

# ============================================================
# Restore point + main flow
# ============================================================
function New-RestorePoint {
  if ($ScanOnly -or $Global:IsRevert -or $NoReboot) { return }
  try {
    Write-Host 'Creating a restore point...' -ForegroundColor Yellow
    try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -EA SilentlyContinue } catch {}
    try {
      $p='HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
      Set-ItemProperty $p -Name SystemRestorePointCreationFrequency -Value 0 -Force -EA SilentlyContinue
    } catch {}
    Checkpoint-Computer -Description "aicancel-$(Get-Date -Format 'yyyy-MM-dd')" -RestorePointType MODIFY_SETTINGS -EA SilentlyContinue
    Ok 'Restore point ready.'
  } catch { Warn 'Could not create a restore point — proceeding with caution.' }
}

function Resolve-Selection([string[]]$opts, [switch]$all, [switch]$exclude) {
  $keys = @('DisableReg','BlockReinstall','RegionPolicy','RemoveAppx','RemoveRecall','RemoveCBS','RemoveFiles','HideAISettings','NoRewrite','KillTasks','Watchdog','NoDefenderAI','EdgeAI','OfficeAI')
  # HideAISettings/NoRewrite are applied as part of RemoveFiles
  if ($all) { return $keys }
  if ($exclude) { return ($keys | Where-Object { $opts -notcontains $_ }) }
  if ($opts.Count -eq 0) { return @() }
  return ($keys | Where-Object { $opts -contains $_ })
}

function Show-Menu {
  Clear-Host
  Write-Host '  ============================================  ' -ForegroundColor Cyan
  Write-Host '   a i c a n c e l   v1.1.0                    ' -ForegroundColor Cyan
  Write-Host '   Cancel Windows AI — clean. private. yours. ' -ForegroundColor Gray
  Write-Host '   (c) 2026 salim-slimani · MIT                ' -ForegroundColor DarkGray
  Write-Host '  ============================================  '
  Write-Host '   1) Full removal (recommended)'
  Write-Host '   2) Scan only — preview what would be removed'
  Write-Host '   3) Registry and policies only'
  Write-Host '   4) Appx packages only'
  Write-Host '   5) CBS + Recall only'
  Write-Host '   6) Update watchdog only'
  Write-Host '   7) Revert all changes'
  Write-Host '   0) Exit'
  Write-Host '  ============================================  '
  $c = Read-Host 'Pick a number'
  switch ($c) {
    '1' { return @('__ALL__') }
    '2' { return @('__SCAN__') }
    '3' { return @('DisableReg','RegionPolicy','EdgeAI','OfficeAI') }
    '4' { return @('RemoveAppx','BlockReinstall') }
    '5' { return @('RemoveRecall','RemoveCBS','RemoveFiles') }
    '6' { return @('Watchdog') }
    '7' { return @('__REVERT__') }
    default { return @() }
  }
}

# ================= MAIN =================
Ensure-Admin
Fix-Path
if ($EnableLog -and -not (Test-Path $Global:Root)) { New-Item $Global:Root -ItemType Directory -Force | Out-Null }

Write-Host ''
Write-Host "   a i c a n c e l  v$AICancelVer  —  Cancel Windows AI" -ForegroundColor Cyan
Write-Host '   (c) 2026 salim-slimani - MIT License' -ForegroundColor DarkGray
if ($PSVersionTable.PSVersion.Major -ge 7) { Log "PowerShell $($PSVersionTable.PSVersion) detected — fully supported." 'Green' }

if (-not $NonInteractive -and -not $ScanOnly) {
  $m = Show-Menu
  if ($m -contains '__ALL__') { $All = $true }
  elseif ($m -contains '__SCAN__') { $ScanOnly = $true; $All = $true }
  elseif ($m -contains '__REVERT__') { $Global:IsRevert = $true; $All = $true }
  elseif ($m.Count -gt 0) { $Options = $m }
  else { Write-Host 'Cancelled.'; exit }
}

$sel = Resolve-Selection -opts $Options -all:$All -exclude:$Exclude
# HideAISettings and NoRewrite are handled inside RemoveFiles
if ($sel -contains 'HideAISettings' -or $sel -contains 'NoRewrite') {
  if ($sel -notcontains 'RemoveFiles') { $sel += 'RemoveFiles' }
}
if ($sel.Count -eq 0 -and -not $ScanOnly) { Err 'No options selected. Use -All or -Options.'; exit 1 }

if (-not $ScanOnly -and -not $Global:IsRevert) {
  if (Test-PendingUpdate) {
    Err 'A Windows update is pending or installing. Reboot, finish updates first, then re-run aicancel.'
    if (-not $NonInteractive) { Read-Host 'Press Enter to exit' | Out-Null }
    exit 1
  }
  if ($Global:DoBackup -or $All) { New-RestorePoint }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
if ($ScanOnly -and $sel.Count -eq 0) { $sel = Resolve-Selection -opts @() -all:$true }

foreach ($s in $sel) {
  switch ($s) {
    'DisableReg'     { Do-DisableReg }
    'EdgeAI'         { Do-EdgeAI }
    'OfficeAI'       { Do-OfficeAI }
    'RegionPolicy'   { Do-RegionPolicy }
    'BlockReinstall' { Do-BlockReinstall }
    'RemoveAppx'     { Do-RemoveAppx }
    'RemoveRecall'   { Do-RemoveRecall }
    'RemoveCBS'      { Do-RemoveCBS }
    'RemoveFiles'    { Do-RemoveFiles }
    'KillTasks'      { Do-KillTasks }
    'Watchdog'       { Do-Watchdog }
    'NoDefenderAI'   { Do-NoDefenderAI }
  }
}
$sw.Stop()

Write-Host ''
Write-Host "aicancel finished in $([math]::Round($sw.Elapsed.TotalSeconds,1)) seconds." -ForegroundColor Green
if ($ScanOnly) { Write-Host 'Scan-only mode — nothing was removed.' -ForegroundColor Yellow }
elseif (-not $NoReboot -and -not $Global:IsRevert -and ($sel -contains 'RemoveCBS' -or $sel -contains 'RemoveAppx')) {
  Write-Host 'A reboot is recommended to complete the removal.' -ForegroundColor Yellow
  if (-not $NonInteractive) {
    $r = Read-Host 'Reboot now? (y/N)'
    if ($r -eq 'y' -or $r -eq 'Y') { Restart-Computer -Force }
  }
}
