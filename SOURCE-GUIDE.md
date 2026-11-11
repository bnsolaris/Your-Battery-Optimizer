# Your Battery Optimizer source guide

| File | Purpose |
| --- | --- |
| `src/App.cs` | Main window, mode controls, tray icon and profile worker |
| `src/SettingsPage.cs` | Settings tab with switches and editable Away mode targets |
| `src/ProfileSettings.cs` | Per-user preferences and validation |
| `src/Setup.cs` | Setup wizard, shortcuts, Windows Apps entry and uninstaller launcher |
| `src/Product.cs` | Product name, version and shared installation paths |
| `src/Translations.json` | English, Turkish, Russian and Spanish text, including the setup terms |
| `src/Localization.cs` | Language selection and text for the Windows executables |
| `src/Localization.ps1` | Shared translations for the profile and uninstall scripts |
| `src/Apply-PowerProfile.ps1` | Display, brightness, volume, wallpaper and power settings, plus restore records |
| `src/Uninstall.ps1` | Removal of installed files, owned shortcuts and the Windows Apps entry |
| `src/BatteryOptimizer.ico` | Battery icon embedded in the app, setup and uninstaller |
| `src/README.txt` | User guide included in the installation |
| `Build.ps1` | Builds the installer and writes the build log |
| `Backup.ps1` | Creates and verifies a dated source and build backup |
| `Build-Signed.ps1` | Builds a package signed with a trusted code-signing certificate |
| `Repair-Uninstall.ps1` | Recovers older installs blocked by an already-restored brightness setting |

Before editing, run `.\Backup.ps1 -Reason "Describe the change"` in Windows
PowerShell. It puts a verified ZIP in the existing adjacent
`Pil-Modu-Yedekler` folder. Keep these backups outside the Git repository.

Run `.\Build.ps1` to build. The installer is written to
`bin/Your-Battery-Optimizer-Setup-<version>.exe` and compiler output goes
to `Build.log`. Run `.\Build-Signed.ps1` for a signed build. See
[SIGNING.md](SIGNING.md) for the certificate requirements.

To edit the setup terms, update `TermsBody` in `src/Translations.json`.
Keep the four language entries and preserve placeholders such as `{0}` in
formatted strings. The wizard starts in the Windows display language when
supported and uses English otherwise. The language chosen in setup is saved
for the app and uninstaller.

Windows groups the main window under `YourBatteryOptimizer.exe`. Setup uses
the icon embedded in that executable for the Windows Apps entry and shortcuts.
