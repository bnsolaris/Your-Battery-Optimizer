# Battery-Mode
Battery Mode helps extend Windows laptop battery life with one-click power profiles. Adjust supported screen refresh rate, brightness, volume, and power settings from the app or system tray, then restore your previous settings with Normal mode.

Outside mode also shows a solid black desktop background. Normal mode restores
the previous background color and re-enables the wallpaper if it was enabled.
Windows keeps the image, placement and slideshow configuration; the app does
not replace or delete wallpaper files. Repeated Outside mode clicks keep the
original restore point, including after an app restart. Restore with Normal
mode before manually changing your wallpaper. Third-party animated wallpapers
are controlled by their own apps.

If the application files were deleted manually, the installer can recover
the leftover Windows installation entry and replace its own stale shortcuts.
Existing app files and unrelated shortcuts are not overwritten. The saved
power-profile restore journal is retained.

Brightness changes are confirmed by reading the actual panel brightness,
including when a driver omits its method return value. An already-restored
value is accepted without issuing another brightness request.

For older installations blocked from uninstalling by a pending brightness
restore, exit the app through its tray menu and run
Pil-Modu-Kaldirma-Yardimcisi.ps1 with Windows PowerShell. It verifies the
original brightness on the matching panel, backs up the journal into the
adjacent Pil-Modu-Yedekler directory, and clears only that verified entry.
It opens the registered uninstaller when no other settings remain pending.

## Development

The Windows app source is in src. Run Derle.ps1 with Windows PowerShell to build
the installer. The output is written to bin. Build output, intermediate files
and local logs are excluded from Git.

Run Yedekle.ps1 before editing project files to create a dated, verified ZIP
in the adjacent Pil-Modu-Yedekler directory. Local builds also create a backup
before starting. GitHub Actions builds use the committed source snapshot.

Source edits can be reviewed and committed with GitHub Desktop. Push the commit
to main to run the Build Windows installer workflow. When it succeeds, download
Pil-Modu-Windows-Unsigned from that run's Artifacts section.

The workflow currently produces unsigned test builds. Windows Smart App Control
may block the installer, application or uninstaller. Code signing requires a
trusted certificate or an approved signing service.

See KAYNAK-REHBERI.md for a source-file guide and IMZALAMA.md for the local
certificate signing workflow.
