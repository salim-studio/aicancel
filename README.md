<p align="center">
  <img src="assets/logo.svg" width="128" alt="aicancel logo — AI crossed out" />
</p>

<h1 align="center">aicancel</h1>

<p align="center"><b>Cancel Windows AI — clean. private. yours.</b></p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-blue" alt="version" />
  <img src="https://img.shields.io/badge/platform-Windows_10_|_11-0078D4" alt="platform" />
  <img src="https://img.shields.io/badge/powershell-5.1_|_7+-5391FE" alt="powershell" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license" />
</p>

---

## What is aicancel?

**aicancel** removes and disables the built-in AI layer of Windows: Copilot, Recall, Click to Do, AI Fabric, Edge AI, Office AI, Defender AI agents and the background services that support them.

It is built for three things:

- **Fast** — one registry batch, one CBS scan, one TrustedInstaller pass. No dead waits.
- **Complete** — 12 modules covering registry, policies, packages, files, tasks and reinstall guards.
- **Safe** — scan-before-you-remove preview, automatic restore point, backup mode and full revert.

## What it removes

| # | Module | What it does |
|---|--------|--------------|
| 1 | `DisableReg` | Disables all `WindowsAI` / `WindowsCopilot` policies, AI consent stores (`generativeAI`, `systemAIModels`), background access, voice activation, telemetry, taskbar Copilot button, Click to Do |
| 2 | `EdgeAI` | Applies 17 Edge AI policies and disables Copilot Mode flags in `Local State` |
| 3 | `OfficeAI` | Disables Copilot in Word / Excel / PowerPoint / OneNote, AI training and content-safety endpoints |
| 4 | `RegionPolicy` | Sets every Copilot / Recall rule in `IntegratedServicesRegionPolicySet.json` to disabled |
| 5 | `BlockReinstall` | Registers Appx removal policies so AI packages are not silently reinstalled |
| 6 | `RemoveAppx` | Removes AI Appx packages (AIX, CoPilot, Copilot Provider, OfficeHub, CoreAI, GameAssist, ActionsServer, WritingAssistant, AIFabric, WindowsWorkload, WinML…) including locked ones |
| 7 | `RemoveRecall` | Disables and strips the Recall optional feature (DISM) |
| 8 | `RemoveCBS` | Reveals and removes hidden AI servicing (CBS) packages in a single scan |
| 9 | `RemoveFiles` | Cleans leftover AI folders/files, hides the AI Components settings page, disables Notepad Rewrite |
| 10 | `KillTasks` | Deletes Windows AI scheduled tasks and their TaskCache entries |
| 11 | `Watchdog` | Installs `aicancel-watchdog` so updates cannot silently bring AI back |
| 12 | `NoDefenderAI` | Disables the Defender AI agent |

## Quick start

```bat
REM Interactive menu (recommended)
aicancel.bat

REM Full silent removal with backup
aicancel.bat -all

REM Preview only — nothing is removed
aicancel.bat -scan

REM Revert everything
aicancel.bat -revert
```

Direct PowerShell:

```powershell
# Interactive menu
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1

# Full silent run with backup + logging
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -All -Backup -EnableLog

# Selected modules only
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -Options DisableReg,RemoveAppx,RemoveCBS

# Everything except one module
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -All -Exclude -Options NoDefenderAI

# Scan only
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -ScanOnly -NonInteractive -All

# Revert
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -All -Revert
```

One-liner (admin PowerShell):

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/salim-studio/aicancel/main/aicancel.ps1')))
```

## Safety first

- Run as **administrator**. The launcher requests elevation automatically.
- Finish pending Windows updates first — aicancel refuses to run while an update is installing or a reboot is pending.
- Use `-Backup` for full runs: a restore point is created automatically.
- Test in a virtual machine first if you are unsure.
- Some antiviruses flag debloat tools as suspicious (false positive). This script is plain-text PowerShell — read it before running.

## Requirements

- Windows 10 / 11 (Pro, Enterprise, Education or Server recommended — Home editions ignore some Group Policy keys by design).
- Windows PowerShell 5.1 **or** PowerShell 7+.

## Files

- `aicancel.ps1` — main script
- `aicancel.bat` — administrator launcher
- `assets/logo.svg` — project logo
- `LICENSE` — MIT license

## License

Copyright (c) 2026 salim-slimani. Released under the [MIT License](LICENSE).
