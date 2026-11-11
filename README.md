# Your Battery Optimizer

Your Battery Optimizer helps you manage battery use on Windows laptops. Set
up **Away mode** with the display and power changes you want, apply it from
the app or notification area, and use **Normal mode** to restore your
previous settings.

## Installation

Setup supports Windows 10 22H2 and Windows 11. Available settings depend
on your Windows version, device and drivers.

1. Open the [Windows installer workflow](https://github.com/bnsolaris/Your-Battery-Optimizer/actions/workflows/build.yml)
   and select a successful run for the version you want. Download
   **Your-Battery-Optimizer-Windows-Unsigned** from **Artifacts**.
2. Extract the ZIP and run the setup EXE. A build from the current source
   produces `Your-Battery-Optimizer-Setup-0.5.0.exe`.
3. Choose a language on the first page and follow the installer. The
   default location is in Program Files, typically
   `C:\Program Files\Your Battery Optimizer`. Setup and the app require
   administrator permissions.

The installer starts in your Windows display language when supported and
otherwise uses English. Choose **English**, **Türkçe**, **Русский** or
**Español**. The app and uninstaller use the language you select.

GitHub Actions produces unsigned test builds. Smart App Control or an
organization's app policies may block them. See [Signing](SIGNING.md)
for details on building a signed installer.

## Configure and use Away mode

1. Open **Overview** to see your current Windows settings. Select
   **Refresh** after changing a value in Windows.
2. Open **Settings**, enable the actions you want and edit their targets.
   Select **Save settings** to keep your preferences for this Windows
   account.
3. Select **Away mode** to apply the saved choices. The result shows
   which changes were applied or skipped.
4. Select **Normal mode** to restore the values saved before Away mode
   changed them.

| Setting | Default Away mode action |
| --- | --- |
| Refresh rate | Aim for 60 Hz using a supported rate |
| Brightness | Target 30% on the internal display |
| Volume | Limit volume to 20% |
| Battery power mode | Use Best power efficiency |
| Energy saver | Set the automatic battery threshold to 100% |
| Desktop background | Show a solid black background |

Each action can be turned off separately. Changing a target or turning
an action off takes effect the next time you apply Away mode. An action
you turned off can still have a saved value from an earlier change.
Normal mode restores that value too. Reapplying Away mode or restarting
the app keeps the original values available for restoration.

Refresh rate and brightness use values supported by the display. The
app skips refresh-rate changes when multiple displays are connected and
shows **Unavailable** when it cannot read a value. Windows keeps your
wallpaper and slideshow configuration while the black background is
shown. Switch to Normal mode before changing your wallpaper manually.

Closing the window keeps the battery icon in the notification area.
Right-click the icon to switch modes, reopen the window or select **Exit**.

## Update or uninstall

Switch to **Normal mode** and select **Exit** from the notification area
before uninstalling. Use **Windows Settings → Apps** or run
`Uninstall.exe` from the installation folder. Uninstall an older copy
before installing the new version.

If you deleted the app files manually, setup can recover the old Windows
installation record once it confirms the files are gone. For an older
version whose uninstaller is blocked by a pending brightness restore,
exit the app and run [Repair-Uninstall.ps1](Repair-Uninstall.ps1) with
Windows PowerShell. It checks the saved brightness against the actual
display value and backs up the restore record before clearing the
verified entry.

## Build from source

Before editing, run `.\Backup.ps1 -Reason "Describe the change"` from the
repository folder in Windows PowerShell. To build the installer, run:

```powershell
.\Build.ps1 -NoPause
```

The build also creates a dated, verified backup before compiling.
Backups go in the adjacent
`Pil-Modu-Yedekler` folder and the installer goes in `bin`.

GitHub Actions runs the profile and installer tests, then builds an
installer when you push to `main`. See the
[GitHub Desktop workflow](GITHUB-DESKTOP.md) and
[source guide](SOURCE-GUIDE.md) for the file layout, translations and
setup terms.

Made with ChatGPT
