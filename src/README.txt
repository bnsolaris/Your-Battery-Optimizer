Your Battery Optimizer 0.5.0

Battery, power and display profiles for Windows 10 22H2 and Windows 11.

Installation

Open Your-Battery-Optimizer-Setup-0.5.0.exe and approve the administrator
prompt. Setup starts in the Windows display language if supported. You can
choose English, Turkish, Russian or Spanish on the first page. The app and
uninstaller use the language selected in setup.

The default folder is C:\Program Files\Your Battery Optimizer. If Windows
uses another drive, setup uses that system's Program Files location.
Launch the app from the Start menu or the optional desktop shortcut.

If files from an older installation still exist, restore your settings
with its Normal mode and run its Uninstall.exe before installing this
version. If you manually deleted the files, setup can recover the old
Windows entry after confirming that its application files are absent.

Using the app

Overview reads your current Windows values when you open the app. Use
Refresh after making changes in Windows. Unavailable readings are marked
in the list.

Open Settings to enable or disable each action. You can set the refresh
rate, brightness, volume and energy saver threshold, and choose a
battery power mode. The default targets are 60 Hz, 30% brightness and
20% volume. Save your choices and select Away mode to apply them.
The result area shows which settings were applied or skipped.
Settings are saved for the current Windows account.

The refresh rate, brightness and volume targets use supported values
without exceeding the original settings. If the display cannot reach the
requested brightness limit, Away mode uses its lowest available value.
Turning an action off skips it the next time you select Away mode.
Normal mode restores every setting recorded before it was changed.

Away mode sets a solid black desktop background. Windows retains the
wallpaper, layout and slideshow settings. Normal mode restores the
previous background. Return to Normal mode before changing your wallpaper
manually. Third-party wallpaper tools manage their own backgrounds.
The battery benefit of a black background is most noticeable on OLED.

Normal mode restores the saved settings. If a screen or audio device was
disconnected or the power plan changed, reconnect the saved device or
select the previous plan and try again. The restore record is kept until
those settings are restored. Brightness is verified against the value
reported by the display.

Closing the window keeps the app in the notification area. Right-click
the battery icon to switch modes or select Exit to close the app.

Uninstalling

Restore settings with Normal mode, then select Exit in the notification
area. Run Uninstall.exe from the installation folder or use Windows
Settings > Apps. Administrator permissions are required. The uninstaller
removes the installed files and owned shortcuts.

Compatibility and signatures

Windows and driver support determines which settings can be changed.
Refresh rate is skipped when more than one display is connected. Vendor
profiles such as PredatorSense Eco are managed by the vendor's app.

Check Digital Signatures in the file's Windows properties to see the
package's signature status. Smart App Control and organizational policies
may block unsigned builds.
