# aicancel — إلغاء ذكاء ويندوز الاصطناعي 🇸🇦

بديل عملي وسريع ومتكامل لمشروع `RemoveWindowsAI`، بنفس التغطية وأكثر، مع تحسينات:

| الميزة | الأصلي | aicancel |
|---|---|---|
| دعم PowerShell 7 | ❌ يمنع ويخرج بخطأ | ✅ مدعوم 5.1 + 7 |
| السرعة | بطيء (sleeps + مسوحات متكررة) | ✅ دفعة ريجستري واحدة + مسح CBS واحد + Trusted مرة واحدة |
| فحص قبل الحذف | ❌ | ✅ `-ScanOnly` |
| نسخ احتياطي + استرجاع | جزئي | ✅ `-Backup` + `-Revert` + نقطة استعادة |
| حماية بعد التحديث | مهمة فحص | ✅ مهمة Watchdog (عند الدخول + أسبوعيا) |
| قائمة عربية | ❌ | ✅ قائمة تفاعلية عربية |
| سجل | اختياري معقد | ✅ `-EnableLog` بسيط |

## ما الذي يزيله؟

1. **DisableReg**: كل سياسات `WindowsAI` + `WindowsCopilot` + Consent (`generativeAI`/`systemAIModels`) + منع `BackgroundAccess` + `VoiceActivation` + `Telemetry` + زر Copilot في شريط المهام + `ClickToDo`
2. **EdgeAI**: 17 سياسة Edge + أعلام `edge-copilot-mode`, `edge-ntp-composer`, `edge-compose` في `Local State`
3. **OfficeAI**: تعطيل Copilot في Word/Excel/PowerPoint/OneNote + `disabletraining` + `disablecontentsafety` + `CopilotPinning`
4. **RegionPolicy**: تصفير كل سياسات Copilot/Recall في `IntegratedServicesRegionPolicySet.json`
5. **BlockReinstall**: سياسات `RemoveDefaultMicrosoftStorePackages` لمنع عودة الحزم
6. **RemoveAppx**: ‏`AIX, CoPilot, Ai.Copilot.Provider, Copilot, OfficeHub, CoreAI, GameAssist, ActionsServer, WritingAssistant, Clipchamp, AIFabric, Handwriting, WindowsWorkload.*, WinML, Voiess/Speion/Livtop/Filons` — إزالة عادية ثم تمريرة TrustedInstaller واحدة (EOL + Deprovisioned + Inbox + NonRemovable)
7. **RemoveRecall**: تعطيل `Disable-WindowsOptionalFeature Recall -Remove` + DISM
8. **RemoveCBS**: كلمات `AIX/Recall/Copilot/CoreAI/AIFabric/PhiSilica/WindowsWorkload/Onnx/WinML/ImageSearch` — إظهار (`Visibility=1`) ثم `Remove-WindowsPackage` ثم تنظيف `servicing\Packages`
9. **RemoveFiles**: مجلدات `WindowsAI` + بقايا `WindowsApps` + إخفاء صفحة `AI Components` + تعطيل `Rewrite` في Notepad
10. **KillTasks**: مهام `WindowsAI/Recall/Copilot/ClickToDo/AIFabric` + مفاتيح `TaskCache`
11. **Watchdog**: مهمة `aicancel-watchdog` تعيد التطبيق بعد التحديثات
12. **NoDefenderAI**: ‏`Set-MpPreference -DisableAIAgent` + حيلة IFEO

## التشغيل

```bat
:: نقرة مزدوجة (قائمة عربية)
aicancel.bat

:: إزالة شاملة صامتة مع نسخة احتياطية
aicancel.bat -all

:: فحص فقط بدون حذف
aicancel.bat -scan

:: استرجاع
aicancel.bat -revert
```

أو PowerShell مباشرة:

```powershell
# تفاعلي
powershell -NoProfile -ExecutionPolicy Bypass -File aicancel.ps1

# شامل صامت
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -All -Backup -EnableLog

# خيارات محددة (متوافق مع أسماء الأصلي أيضا)
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -Options DisableReg,RemoveAppx,RemoveCBS

# استثناء
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -All -Exclude -Options NoDefenderAI

# فحص
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -ScanOnly -NonInteractive -All

# استرجاع
powershell -NoProfile -ExecutionPolicy Bypass -File .\aicancel.ps1 -NonInteractive -All -Revert
```

## تحذيرات

- شغّله كمسؤول، وأكمل تحديثات ويندوز المعلقة أولا (يفحص تلقائيا ويرفض المتابعة إن وُجد تحديث معلق).
- نسخة Home لا تطبق كل سياسات GroupPolicy مثل Pro/Enterprise — هذا قيد من ويندوز نفسه.
- بعض مضادات الفيروسات قد تعطي False Positive (طبيعي لأي أداة Debloat) — جرّب في VM أولا إن قلقت.
- استخدم `-Backup` دائما قبل الإزالة الشاملة.

## الملفات

- `aicancel.ps1` — السكربت الرئيسي
- `aicancel.bat` — مشغّل بصلاحيات مسؤول
- `README.md` — هذا الملف

MIT — مبني بفكرة مستوحاة من zoicware/RemoveWindowsAI مع إعادة كتابة كاملة وتحسينات سرعة وتوافق.
