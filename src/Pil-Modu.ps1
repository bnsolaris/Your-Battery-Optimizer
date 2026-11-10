[CmdletBinding()]
param(
    [ValidateSet('Disari', 'Normal', 'Durum')]
    [string]$Mode = 'Durum',

    [ValidateRange(0, 100)]
    [int]$DisariParlaklik = 30,

    [ValidateRange(0, 100)]
    [int]$DisariSes = 20,

    [ValidateRange(1, 360)]
    [int]$DisariHz = 60
)
$ErrorActionPreference = 'Stop'
if (-not ('PilModu.NativeDisplay' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace PilModu {
    public static class NativeDisplay {
        public const int ENUM_CURRENT_SETTINGS = -1;
        public const int DISP_CHANGE_SUCCESSFUL = 0;
        public const int DM_DISPLAYFREQUENCY = 0x00400000;
        public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x1;
        public const int DISPLAY_DEVICE_MIRRORING_DRIVER = 0x8;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct DISPLAY_DEVICE {
            public int cb;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
            public int StateFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        private static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        private static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

        [DllImport("user32.dll", CharSet = CharSet.Ansi)]
        private static extern int ChangeDisplaySettingsEx(string deviceName, ref DEVMODE devMode, IntPtr hwnd, uint flags, IntPtr lParam);

        public static Dictionary<string, int> GetRefreshRates() {
            var result = new Dictionary<string, int>();
            for (uint index = 0; ; index++) {
                var display = new DISPLAY_DEVICE();
                display.cb = Marshal.SizeOf(display);
                if (!EnumDisplayDevices(null, index, ref display, 0)) break;
                bool attached = (display.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0;
                bool mirror = (display.StateFlags & DISPLAY_DEVICE_MIRRORING_DRIVER) != 0;
                if (!attached || mirror) continue;

                var current = NewDevMode();
                if (EnumDisplaySettings(display.DeviceName, ENUM_CURRENT_SETTINGS, ref current)) {
                    result[display.DeviceName] = current.dmDisplayFrequency;
                }
            }
            return result;
        }

        public static int GetCurrentRefreshRate() {
            var current = NewDevMode();
            return EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref current)
                ? current.dmDisplayFrequency : 0;
        }

        public static string GetSingleDisplayId() {
            var names = GetRefreshRates();
            if (names.Count != 1) return null;
            foreach (var name in names.Keys) {
                var monitor = new DISPLAY_DEVICE();
                monitor.cb = Marshal.SizeOf(monitor);
                if (EnumDisplayDevices(name, 0, ref monitor, 1) &&
                    !string.IsNullOrEmpty(monitor.DeviceID))
                    return name + "|" + monitor.DeviceID;
            }
            return null;
        }

        public static int SelectRefreshRate(int preferred) {
            var current = NewDevMode();
            if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref current)) return 0;
            int best = current.dmDisplayFrequency;
            if (best <= preferred) return best;
            for (int index = 0; ; index++) {
                var candidate = NewDevMode();
                if (!EnumDisplaySettings(null, index, ref candidate)) break;
                int frequency = candidate.dmDisplayFrequency;
                if (candidate.dmPelsWidth != current.dmPelsWidth ||
                    candidate.dmPelsHeight != current.dmPelsHeight ||
                    candidate.dmBitsPerPel != current.dmBitsPerPel ||
                    candidate.dmDisplayFlags != current.dmDisplayFlags ||
                    frequency <= 1 || frequency >= current.dmDisplayFrequency) continue;
                if (best == current.dmDisplayFrequency ||
                    Math.Abs(frequency - preferred) < Math.Abs(best - preferred) ||
                    (Math.Abs(frequency - preferred) == Math.Abs(best - preferred) && frequency < best))
                    best = frequency;
            }
            return best;
        }

        public static void SetSingleRefreshRate(string displayId, int targetHz) {
            if (displayId == null || displayId != GetSingleDisplayId())
                throw new InvalidOperationException("Kaydedilen tek ekran bağlı değil.");
            var current = NewDevMode();
            if (!EnumDisplaySettings(null, ENUM_CURRENT_SETTINGS, ref current))
                throw new InvalidOperationException("Ekran ayarı okunamadı.");
            if (current.dmDisplayFrequency == targetHz) return;
            current.dmFields = DM_DISPLAYFREQUENCY;
            current.dmDisplayFrequency = targetHz;
            if (ChangeDisplaySettingsEx(null, ref current, IntPtr.Zero, 2, IntPtr.Zero) != DISP_CHANGE_SUCCESSFUL ||
                ChangeDisplaySettingsEx(null, ref current, IntPtr.Zero, 0, IntPtr.Zero) != DISP_CHANGE_SUCCESSFUL ||
                GetCurrentRefreshRate() != targetHz)
                throw new InvalidOperationException("Ekran " + targetHz + " Hz değerine geçemedi.");
        }

        public static string SetRefreshRate(int targetHz) {
            var messages = new List<string>();
            for (uint index = 0; ; index++) {
                var display = new DISPLAY_DEVICE();
                display.cb = Marshal.SizeOf(display);
                if (!EnumDisplayDevices(null, index, ref display, 0)) break;
                bool attached = (display.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) != 0;
                bool mirror = (display.StateFlags & DISPLAY_DEVICE_MIRRORING_DRIVER) != 0;
                if (!attached || mirror) continue;

                var current = NewDevMode();
                if (!EnumDisplaySettings(display.DeviceName, ENUM_CURRENT_SETTINGS, ref current)) continue;

                bool supported = false;
                for (int modeIndex = 0; ; modeIndex++) {
                    var candidate = NewDevMode();
                    if (!EnumDisplaySettings(display.DeviceName, modeIndex, ref candidate)) break;
                    if (candidate.dmPelsWidth == current.dmPelsWidth &&
                        candidate.dmPelsHeight == current.dmPelsHeight &&
                        candidate.dmDisplayFrequency == targetHz) {
                        supported = true;
                        break;
                    }
                }

                if (!supported) {
                    messages.Add(targetHz + " Hz bir ekranda desteklenmiyor");
                    continue;
                }

                current.dmFields = DM_DISPLAYFREQUENCY;
                current.dmDisplayFrequency = targetHz;
                int code = ChangeDisplaySettingsEx(display.DeviceName, ref current, IntPtr.Zero, 0, IntPtr.Zero);
                if (code != DISP_CHANGE_SUCCESSFUL)
                    messages.Add("Bir ekranın yenileme hızı değiştirilemedi (hata kodu " + code + ")");
            }
            return string.Join("; ", messages);
        }

        private static DEVMODE NewDevMode() {
            var mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(mode);
            return mode;
        }
    }

    public static class NativePower {
        [DllImport("powrprof.dll")]
        private static extern uint PowerGetUserConfiguredDCPowerMode(out Guid powerModeGuid);

        [DllImport("powrprof.dll")]
        private static extern uint PowerSetUserConfiguredDCPowerMode(ref Guid powerModeGuid);

        [DllImport("powrprof.dll")]
        private static extern uint PowerGetActiveScheme(IntPtr userRootPowerKey, out IntPtr activePolicyGuid);

        [DllImport("powrprof.dll")]
        private static extern uint PowerReadDCValueIndex(IntPtr rootPowerKey, ref Guid schemeGuid, ref Guid subgroupGuid, ref Guid settingGuid, out uint valueIndex);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr hMem);

        public static void SetBestEfficiency() {
            var mode = new Guid("961cc777-2547-4f9d-8174-7d86181b8a7a");
            uint result = PowerSetUserConfiguredDCPowerMode(ref mode);
            if (result != 0) throw new InvalidOperationException("Güç modu ayarlanamadı. Hata: " + result);
        }

        public static Guid GetDCMode() {
            Guid mode;
            uint result = PowerGetUserConfiguredDCPowerMode(out mode);
            if (result != 0) throw new InvalidOperationException("Pil güç modu okunamadı. Hata: " + result);
            return mode;
        }

        public static void SetDCMode(Guid mode) {
            uint result = PowerSetUserConfiguredDCPowerMode(ref mode);
            if (result != 0) throw new InvalidOperationException("Pil güç modu ayarlanamadı. Hata: " + result);
        }

        public static void SetBalanced() {
            var mode = Guid.Empty;
            uint result = PowerSetUserConfiguredDCPowerMode(ref mode);
            if (result != 0) throw new InvalidOperationException("Güç modu ayarlanamadı. Hata: " + result);
        }

        public static Guid GetActiveScheme() {
            IntPtr pointer;
            uint result = PowerGetActiveScheme(IntPtr.Zero, out pointer);
            if (result != 0) throw new InvalidOperationException("Etkin güç planı okunamadı. Hata: " + result);
            try { return (Guid)Marshal.PtrToStructure(pointer, typeof(Guid)); }
            finally { LocalFree(pointer); }
        }

        public static uint ReadDCValue(Guid subgroup, Guid setting) {
            Guid scheme = GetActiveScheme();
            uint value;
            uint result = PowerReadDCValueIndex(IntPtr.Zero, ref scheme, ref subgroup, ref setting, out value);
            if (result != 0) throw new InvalidOperationException("DC güç ayarı okunamadı. Hata: " + result);
            return value;
        }
    }

    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDesktopWallpaper {
        [PreserveSig] int SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [PreserveSig] int GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorId, [MarshalAs(UnmanagedType.LPWStr)] out string wallpaper);
        [PreserveSig] int GetMonitorDevicePathAt(uint index, [MarshalAs(UnmanagedType.LPWStr)] out string monitorId);
        [PreserveSig] int GetMonitorDevicePathCount(out uint count);
        [PreserveSig] int GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorId, out WallpaperRect rect);
        [PreserveSig] int SetBackgroundColor(uint color);
        [PreserveSig] int GetBackgroundColor(out uint color);
        [PreserveSig] int SetPosition(int position);
        [PreserveSig] int GetPosition(out int position);
        [PreserveSig] int SetSlideshow(IntPtr items);
        [PreserveSig] int GetSlideshow(out IntPtr items);
        [PreserveSig] int SetSlideshowOptions(uint options, uint milliseconds);
        [PreserveSig] int GetSlideshowOptions(out uint options, out uint milliseconds);
        [PreserveSig] int AdvanceSlideshow([MarshalAs(UnmanagedType.LPWStr)] string monitorId, int direction);
        [PreserveSig] int GetStatus(out uint state);
        [PreserveSig] int Enable([MarshalAs(UnmanagedType.Bool)] bool enable);
    }

    [StructLayout(LayoutKind.Sequential)]
    struct WallpaperRect { public int Left, Top, Right, Bottom; }

    [ComImport, Guid("C2CF3110-460E-4FC1-B9D0-8A1C0C9CC4BD")]
    class DesktopWallpaperComObject { }

    public sealed class WallpaperState {
        public uint Color { get; set; }
        public bool Enabled { get; set; }
    }

    public static class NativeWallpaper {
        private static WallpaperState ReadState(IDesktopWallpaper desktop) {
            uint status, color;
            Marshal.ThrowExceptionForHR(desktop.GetStatus(out status));
            if ((status & 4) != 0)
                throw new InvalidOperationException("Uzak oturumda duvar kâğıdı değişikliği atlandı.");
            Marshal.ThrowExceptionForHR(desktop.GetBackgroundColor(out color));
            return new WallpaperState { Color = color, Enabled = (status & 1) != 0 };
        }

        public static WallpaperState GetState() {
            var desktop = (IDesktopWallpaper)new DesktopWallpaperComObject();
            try { return ReadState(desktop); }
            finally { Marshal.ReleaseComObject(desktop); }
        }

        public static void SetBackground(uint color, bool enabled) {
            var desktop = (IDesktopWallpaper)new DesktopWallpaperComObject();
            try {
                ReadState(desktop);
                Marshal.ThrowExceptionForHR(desktop.SetBackgroundColor(color));
                // Disable the image instead of replacing it. Windows retains the
                // wallpaper paths, placement and slideshow configuration for restore.
                Marshal.ThrowExceptionForHR(desktop.Enable(enabled));
                var actual = ReadState(desktop);
                if (actual.Color != color || actual.Enabled != enabled)
                    throw new InvalidOperationException("Windows arka plan değişikliğini uygulamadı.");
            }
            finally { Marshal.ReleaseComObject(desktop); }
        }
    }

    public enum EDataFlow { eRender, eCapture, eAll }
    public enum ERole { eConsole, eMultimedia, eCommunications }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid id, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
        [PreserveSig] int OpenPropertyStore(int access, out IntPtr store);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
    }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int NotImpl1();
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float levelDb, IntPtr context);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, IntPtr context);
        [PreserveSig] int GetMasterVolumeLevel(out float levelDb);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDb, IntPtr context);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, IntPtr context);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDb);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, IntPtr context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    public static class Audio {
        private static IMMDevice Device() {
            var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice device;
            Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device));
            return device;
        }

        public static string GetDeviceId() {
            string id;
            Marshal.ThrowExceptionForHR(Device().GetId(out id));
            return id;
        }

        private static IAudioEndpointVolume Endpoint() {
            return Endpoint(Device());
        }

        private static IAudioEndpointVolume Endpoint(IMMDevice device) {
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object endpoint;
            Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out endpoint));
            return (IAudioEndpointVolume)endpoint;
        }

        public static float GetVolume() {
            float value;
            Marshal.ThrowExceptionForHR(Endpoint().GetMasterVolumeLevelScalar(out value));
            return value;
        }

        public static bool GetMute() {
            bool value;
            Marshal.ThrowExceptionForHR(Endpoint().GetMute(out value));
            return value;
        }

        public static void SetVolume(float value) {
            value = Math.Max(0, Math.Min(1, value));
            Marshal.ThrowExceptionForHR(Endpoint().SetMasterVolumeLevelScalar(value, IntPtr.Zero));
        }

        public static void SetDeviceVolume(string expectedId, float value) {
            var device = Device();
            string id;
            Marshal.ThrowExceptionForHR(device.GetId(out id));
            if (id != expectedId) throw new InvalidOperationException("Kaydedilen ses çıkışı etkin değil.");
            value = Math.Max(0, Math.Min(1, value));
            Marshal.ThrowExceptionForHR(Endpoint(device).SetMasterVolumeLevelScalar(value, IntPtr.Zero));
        }

        public static void SetMute(bool value) {
            Marshal.ThrowExceptionForHR(Endpoint().SetMute(value, IntPtr.Zero));
        }
    }
}
'@
}
$ErrorActionPreference = 'Stop'
$stateDirectory = Join-Path $env:LOCALAPPDATA 'PilModuProfile'
$statePath = Join-Path $stateDirectory 'onceki-ayarlar.json'
$thresholdGroup = [guid]'de830923-a562-41af-a086-e3a2c6bad2da'
$thresholdSetting = [guid]'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'
$steps = [ordered]@{}
$journal = @{}

function Save-Journal {
    if ($journal.Count -eq 0) {
        if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath }
        return
    }
    [void][IO.Directory]::CreateDirectory($stateDirectory)
    $pendingPath = "$statePath.new"
    [IO.File]::WriteAllText($pendingPath, ($journal | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
    if ([IO.File]::Exists($statePath)) {
        [IO.File]::Replace($pendingPath, $statePath, [NullString]::Value)
    }
    else {
        [IO.File]::Move($pendingPath, $statePath)
    }
}

function New-Setting($Id, $Label, [scriptblock]$Read, [scriptblock]$Write) {
    $steps[$Id] = @{ Label = $Label; Read = $Read; Write = $Write }
}

function Test-Battery {
    Add-Type -AssemblyName System.Windows.Forms
    $status = [Windows.Forms.SystemInformation]::PowerStatus.BatteryChargeStatus
    if ($status -eq 'Unknown' -or ($status -band [Windows.Forms.BatteryChargeStatus]::NoSystemBattery)) {
        throw 'Windows kullanılabilir bir pil bildirmiyor.'
    }
}

New-Setting 'Display' 'Yenileme hızı' {
    $id = [PilModu.NativeDisplay]::GetSingleDisplayId()
    if (-not $id) { throw 'Kimliği okunabilen tek bir ekran bağlı olmalı.' }
    $current = [PilModu.NativeDisplay]::GetCurrentRefreshRate()
    if ($current -le 1) { throw 'Geçerli hız okunamadı.' }
    @{ Id = $id; Value = $current; Target = [PilModu.NativeDisplay]::SelectRefreshRate($DisariHz) }
} {
    param($entry, $value)
    [PilModu.NativeDisplay]::SetSingleRefreshRate($entry.Id, [int]$value)
    Write-Host ('Ekran Heartz Değeri: {0} Hz' -f [PilModu.NativeDisplay]::GetCurrentRefreshRate())
}

New-Setting 'Brightness' 'Parlaklık' {
    $panels = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness | Where-Object Active)
    if ($panels.Count -ne 1) { throw 'Windows tek bir dahili ekran için parlaklık kontrolü sunmuyor.' }
    $levels = @($panels[0].Level | Where-Object { $_ -gt 0 -and $_ -lt $panels[0].CurrentBrightness } |
        Sort-Object { [math]::Abs([int]$_ - $DisariParlaklik) })
    $current = [int]$panels[0].CurrentBrightness
    $target = if ($current -gt $DisariParlaklik -and $levels.Count) { [int]$levels[0] } else { $current }
    @{ Id = $panels[0].InstanceName; Value = $current; Target = $target }
} {
    param($entry, $value)
    $panel = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods |
        Where-Object { $_.Active -and $_.InstanceName -eq $entry.Id } | Select-Object -First 1
    if (-not $panel) { throw 'Kaydedilen dahili ekran erişilebilir değil.' }
    $change = Invoke-CimMethod -InputObject $panel -MethodName WmiSetBrightness -Arguments @{
        Timeout = [uint32]0; Brightness = [byte]$value
    }
    if ($change.ReturnValue -ne 0) { throw "Ekran sürücüsü parlaklık isteğini reddetti ($($change.ReturnValue))." }
    Write-Host "Parlaklık: %$value"
}

New-Setting 'Audio' 'Ses' {
    $id = [PilModu.Audio]::GetDeviceId()
    $current = [PilModu.Audio]::GetVolume()
    if ($id -ne [PilModu.Audio]::GetDeviceId()) { throw 'Ses çıkışı işlem sırasında değişti.' }
    @{ Id = $id; Value = $current; Target = [math]::Min($current, $DisariSes / 100.0) }
} {
    param($entry, $value)
    [PilModu.Audio]::SetDeviceVolume($entry.Id, [single]$value)
    Write-Host ('Ses: %{0}' -f [math]::Round($value * 100))
}

New-Setting 'Power' 'Pil güç modu' {
    Test-Battery
    @{ Value = [PilModu.NativePower]::GetDCMode().ToString(); Target = '961cc777-2547-4f9d-8174-7d86181b8a7a' }
} {
    param($entry, $value)
    [PilModu.NativePower]::SetDCMode([guid]$value)
    Write-Host 'Pil güç modu ayarlandı.'
}

New-Setting 'Saver' 'Enerji tasarrufu eşiği' {
    Test-Battery
    $scheme = [PilModu.NativePower]::GetActiveScheme()
    $value = [PilModu.NativePower]::ReadDCValue($thresholdGroup, $thresholdSetting)
    if ($scheme -ne [PilModu.NativePower]::GetActiveScheme()) { throw 'Güç planı işlem sırasında değişti.' }
    @{ Id = $scheme.ToString(); Value = $value; Target = 100 }
} {
    param($entry, $value)
    if ([guid]$entry.Id -ne [PilModu.NativePower]::GetActiveScheme()) {
        throw 'Geri dönmek için kaydedilen güç planını yeniden seç.'
    }
    & (Join-Path ([Environment]::SystemDirectory) 'powercfg.exe') /setdcvalueindex $entry.Id $thresholdGroup $thresholdSetting $value | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Windows tasarruf eşiği değişikliğini kabul etmedi.' }
    & (Join-Path ([Environment]::SystemDirectory) 'powercfg.exe') /setactive $entry.Id | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Windows güç planını yeniden etkinleştiremedi.' }
    Write-Host "Pilde otomatik tasarruf eşiği: %$value"
}

New-Setting 'Wallpaper' 'Duvar kâğıdı' {
    $current = [PilModu.NativeWallpaper]::GetState()
    $value = if (-not $current.Enabled -and $current.Color -eq 0) {
        'Black'
    } else {
        @{ Color = $current.Color; Enabled = $current.Enabled }
    }
    @{ Value = $value; Target = 'Black' }
} {
    param($entry, $value)
    if ($value -is [string] -and $value -eq 'Black') {
        [PilModu.NativeWallpaper]::SetBackground(0, $false)
        Write-Host 'Duvar kâğıdı: siyah arka plan.'
    }
    else {
        [PilModu.NativeWallpaper]::SetBackground([uint32]$value.Color, [bool]$value.Enabled)
        Write-Host 'Duvar kâğıdı: önceki arka plan geri yüklendi.'
    }
}

function Invoke-Profile {
    if ($Mode -ne 'Durum' -and (Test-Path -LiteralPath $statePath)) {
        $saved = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        foreach ($property in $saved.PSObject.Properties) {
            if (-not $steps.Contains($property.Name)) { throw 'Geri yükleme kaydının sürümü desteklenmiyor.' }
            $journal[$property.Name] = $property.Value
        }
    }
    if ($Mode -eq 'Normal' -and $journal.Count -eq 0) {
        Write-Host 'Geri yüklenecek ayar yok.'
        return
    }

    $completed = 0
    $settingIds = if ($Mode -eq 'Normal') {
        # Restore the saver threshold before the configured power mode.
        'Saver', 'Power', 'Audio', 'Brightness', 'Display', 'Wallpaper'
    } else { $steps.Keys }
    foreach ($id in $settingIds) {
        $step = $steps[$id]
        try {
            if ($Mode -eq 'Normal') {
                if (-not $journal.ContainsKey($id)) { continue }
                $entry = $journal[$id]
                & $step.Write $entry $entry.Value
                $journal.Remove($id)
                Save-Journal
            }
            elseif ($Mode -eq 'Durum') {
                $entry = & $step.Read
                Write-Host "$($step.Label): kullanılabilir."
            }
            else {
                if (-not $journal.ContainsKey($id)) {
                    $entry = & $step.Read
                    if ($entry.Value -eq $entry.Target) {
                        Write-Host "$($step.Label): mevcut değer korundu."
                        $completed++
                        continue
                    }
                    $journal[$id] = $entry
                    try { Save-Journal }
                    catch { $journal.Remove($id); throw }
                }
                $entry = $journal[$id]
                & $step.Write $entry $entry.Target
            }
            $completed++
        }
        catch {
            Write-Host "$($step.Label): atlandı. $($_.Exception.Message)"
        }
    }
    if ($Mode -eq 'Normal' -and ($journal.Count -gt 0 -or (Test-Path -LiteralPath $statePath))) {
        throw 'Bazı ayarlar geri yüklenemedi. Kayıt saklandı. Yukarıdaki koşulları sağlayıp tekrar dene.'
    }
    if ($Mode -eq 'Disari' -and $completed -eq 0) {
        throw 'Bu cihazda profil uygulanamadı.'
    }
}

$lock = [Threading.Mutex]::new($false, 'Local\PilModu.General.Profile')
$ownsLock = $false
try {
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Başka bir profil işlemi sürüyor.' }
    Invoke-Profile
}
finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
