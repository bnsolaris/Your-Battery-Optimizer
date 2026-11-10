# Battery-Mode
Pil Modu helps extend Windows laptop battery life with one-click power profiles. Adjust supported screen refresh rate, brightness, volume, and power settings from the app or system tray, then restore your previous settings with Normal mode.

## Development

The Windows app source is in src. Run Derle.ps1 with Windows PowerShell to build
the installer. The output is written to bin. Build output, intermediate files
and local logs are excluded from Git.

Source edits can be reviewed and committed with GitHub Desktop. Push the commit
to main to run the Build Windows installer workflow. When it succeeds, download
Pil-Modu-Windows-Unsigned from that run's Artifacts section.

The workflow currently produces unsigned test builds. Windows Smart App Control
may block the installer, application or uninstaller. Code signing requires a
trusted certificate or an approved signing service.

See KAYNAK-REHBERI.md for a source-file guide and IMZALAMA.md for the local
certificate signing workflow.
