# Back up before changing this project

The user requires a dated backup before each development change.

- Before editing, replacing, renaming, or deleting project files, run
  Backup.ps1 from this repository with a short Reason describing the change.
- A single verified backup may cover one coherent change set. Take another
  backup before starting a separate change set.
- If creating or verifying the backup fails, stop before modifying files.
- Read-only inspection does not need a backup.
- Build.ps1 takes its own pre-build backup for local builds. GitHub Actions
  builds use the pushed Git commit as their source snapshot.
- Backups belong in the adjacent Pil-Modu-Yedekler directory. Keep them out
  of the repository. Preserve existing backups.
- User source edits and customizations must be preserved.

Example command

    powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Backup.ps1 -Reason "Before changing installer layout"
