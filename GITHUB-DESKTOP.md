# Build updates with GitHub Desktop

Add this source folder to GitHub Desktop as an existing repository. It is
the folder that contains `Build.ps1` and `src`.

1. Run `Backup.ps1` before making a change. The dated, verified ZIP goes in
   the adjacent `Pil-Modu-Yedekler` folder.
2. Review the changed files in GitHub Desktop. Commit the source updates
   with a descriptive message.
3. Select **Push origin** to send the commit to `main`.
4. In GitHub, open **Actions** and select the **Build Windows installer** run
   for that commit.
5. When it succeeds, download **Your-Battery-Optimizer-Windows-Unsigned**
   from the run's **Artifacts** section.

The workflow builds the Windows installer from the pushed source. Its
artifact is an unsigned test build. The signing requirements are in
[SIGNING.md](SIGNING.md).
