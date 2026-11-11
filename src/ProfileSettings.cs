using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;

namespace BatteryOptimizer
{
    internal sealed class ProfileSettings
    {
        public bool Display { get; set; }
        public bool Brightness { get; set; }
        public bool Audio { get; set; }
        public bool Power { get; set; }
        public bool Saver { get; set; }
        public bool Wallpaper { get; set; }
        public int RefreshRate { get; set; }
        public int BrightnessPercent { get; set; }
        public int VolumePercent { get; set; }
        public int SaverPercent { get; set; }
        public string PowerMode { get; set; }

        internal static readonly string[] PowerModes = { "Efficiency", "Balanced", "Performance" };

        public ProfileSettings()
        {
            Display = Brightness = Audio = Power = Saver = Wallpaper = true;
            RefreshRate = 60;
            BrightnessPercent = 30;
            VolumePercent = 20;
            SaverPercent = 100;
            PowerMode = PowerModes[0];
        }

        internal bool HasEnabledSettings
        {
            get { return Display || Brightness || Audio || Power || Saver || Wallpaper; }
        }

        internal string DisabledSettings()
        {
            var names = new List<string>();
            if (!Display) names.Add("Display");
            if (!Brightness) names.Add("Brightness");
            if (!Audio) names.Add("Audio");
            if (!Power) names.Add("Power");
            if (!Saver) names.Add("Saver");
            if (!Wallpaper) names.Add("Wallpaper");
            return string.Join(",", names);
        }

        internal static ProfileSettings Load(string path)
        {
            string json;
            try { json = File.ReadAllText(path, Encoding.UTF8); }
            catch (FileNotFoundException) { return new ProfileSettings(); }
            catch (DirectoryNotFoundException) { return new ProfileSettings(); }
            var settings = new JavaScriptSerializer().Deserialize<ProfileSettings>(json);
            if (settings == null) throw new InvalidDataException("Profile settings are empty.");
            settings.Validate();
            return settings;
        }

        internal void Save(string path)
        {
            Validate();
            string directory = Path.GetDirectoryName(path);
            Directory.CreateDirectory(directory);
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("The profile settings folder is a link.");
            if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("The profile settings file is a link.");
            string temporary = Path.Combine(directory, ".profile-settings-" + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                File.WriteAllText(temporary, new JavaScriptSerializer().Serialize(this), new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temporary, path, null);
                else File.Move(temporary, path);
            }
            finally
            {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }

        private void Validate()
        {
            if (RefreshRate < 1 || RefreshRate > 360 || BrightnessPercent < 0 || BrightnessPercent > 100 ||
                VolumePercent < 0 || VolumePercent > 100 || SaverPercent < 0 || SaverPercent > 100 ||
                Array.IndexOf(PowerModes, PowerMode) < 0)
                throw new InvalidDataException("A profile setting is out of range.");
        }
    }
}
