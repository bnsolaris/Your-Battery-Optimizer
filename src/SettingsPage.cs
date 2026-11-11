using System;
using System.Drawing;
using System.Windows.Forms;

namespace BatteryOptimizer
{
    internal sealed class SettingsPage : UserControl
    {
        private readonly string path;
        private readonly CheckBox display = Toggle("Display");
        private readonly CheckBox brightness = Toggle("Brightness");
        private readonly CheckBox audio = Toggle("Audio");
        private readonly CheckBox power = Toggle("Power");
        private readonly CheckBox saver = Toggle("Saver");
        private readonly CheckBox wallpaper = Toggle("BlackWallpaperSetting");
        private readonly NumericUpDown refreshRate = Number(1, 360);
        private readonly NumericUpDown brightnessPercent = Number(0, 100);
        private readonly NumericUpDown volumePercent = Number(0, 100);
        private readonly NumericUpDown saverPercent = Number(0, 100);
        private readonly ComboBox powerMode = new ComboBox();
        private readonly Label message = new Label { AutoSize = true, Margin = new Padding(10, 10, 0, 0) };
        private readonly Button save = new Button { AutoSize = true, MinimumSize = new Size(125, 34) };

        internal ProfileSettings SavedSettings { get; private set; }
        internal bool HasUnsavedChanges { get; private set; }

        internal SettingsPage(string path)
        {
            this.path = path;
            Dock = DockStyle.Fill;
            BackColor = Color.White;
            ProfileSettings initial;
            try { initial = SavedSettings = ProfileSettings.Load(path); }
            catch
            {
                initial = new ProfileSettings();
                message.Text = UiText.Get("SettingsReadFailed");
            }

            var scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true, Padding = new Padding(14) };
            var layout = new TableLayoutPanel
            {
                Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, ColumnCount = 1
            };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            scroll.Controls.Add(layout);
            Controls.Add(scroll);
            layout.Controls.Add(new Label
            {
                Text = UiText.Get("AwaySettingsTitle"), Font = new Font("Segoe UI Semibold", 13),
                AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 0, 0, 7)
            });
            layout.Controls.Add(new Label
            {
                Text = UiText.Get("SettingsHint"), AutoSize = true, Dock = DockStyle.Top,
                ForeColor = Color.FromArgb(74, 90, 110), Margin = new Padding(0, 0, 0, 12)
            });

            powerMode.DropDownStyle = ComboBoxStyle.DropDownList;
            powerMode.Dock = DockStyle.Fill;
            foreach (string option in ProfileSettings.PowerModes) powerMode.Items.Add(UiText.Get("PowerMode" + option));

            display.Checked = initial.Display;
            brightness.Checked = initial.Brightness;
            audio.Checked = initial.Audio;
            power.Checked = initial.Power;
            saver.Checked = initial.Saver;
            wallpaper.Checked = initial.Wallpaper;
            refreshRate.Value = initial.RefreshRate;
            brightnessPercent.Value = initial.BrightnessPercent;
            volumePercent.Value = initial.VolumePercent;
            saverPercent.Value = initial.SaverPercent;
            powerMode.SelectedIndex = Array.IndexOf(ProfileSettings.PowerModes, initial.PowerMode);

            var rows = new TableLayoutPanel
            {
                Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, ColumnCount = 2
            };
            rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58));
            rows.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42));
            AddRow(rows, display, refreshRate, "Hz");
            AddRow(rows, brightness, brightnessPercent, "%");
            AddRow(rows, audio, volumePercent, "%");
            AddRow(rows, power, powerMode, null);
            AddRow(rows, saver, saverPercent, "%");
            AddRow(rows, wallpaper, null, null);
            layout.Controls.Add(rows);

            var actions = new FlowLayoutPanel
            {
                AutoSize = true, WrapContents = true, Dock = DockStyle.Top, Margin = new Padding(0, 10, 0, 0)
            };
            save.Text = UiText.Get("SaveSettings");
            save.Click += SaveSettings;
            save.Enabled = SavedSettings == null;
            actions.Controls.Add(save);
            actions.Controls.Add(message);
            layout.Controls.Add(actions);

            foreach (NumericUpDown number in new[] { refreshRate, brightnessPercent, volumePercent, saverPercent })
            {
                number.ValueChanged += MarkDirty;
                number.TextChanged += MarkDirty;
            }
            powerMode.SelectedIndexChanged += MarkDirty;
        }

        private static CheckBox Toggle(string key)
        {
            return new CheckBox { Text = UiText.Get(key), AutoSize = true, Dock = DockStyle.Top, Margin = new Padding(0, 7, 10, 7) };
        }

        private static NumericUpDown Number(int minimum, int maximum)
        {
            return new NumericUpDown { Minimum = minimum, Maximum = maximum, Width = 82, TextAlign = HorizontalAlignment.Right };
        }

        private void AddRow(TableLayoutPanel rows, CheckBox toggle, Control editor, string unit)
        {
            int row = rows.RowCount++;
            rows.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            rows.Controls.Add(toggle, 0, row);
            if (editor != null)
            {
                editor.AccessibleName = toggle.Text;
                editor.Enabled = toggle.Checked;
                if (unit == null)
                    rows.Controls.Add(editor, 1, row);
                else
                {
                    var input = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Dock = DockStyle.Top, Margin = Padding.Empty };
                    input.Controls.Add(editor);
                    input.Controls.Add(new Label { Text = unit, AutoSize = true, Margin = new Padding(3, 7, 0, 0) });
                    rows.Controls.Add(input, 1, row);
                }
            }
            toggle.CheckedChanged += delegate
            {
                if (editor != null) editor.Enabled = toggle.Checked;
                MarkDirty(this, EventArgs.Empty);
            };
        }

        private void MarkDirty(object sender, EventArgs args)
        {
            HasUnsavedChanges = true;
            save.Enabled = true;
            message.Text = UiText.Get("UnsavedSettings");
        }

        private void SaveSettings(object sender, EventArgs args)
        {
            var settings = new ProfileSettings
            {
                Display = display.Checked, Brightness = brightness.Checked, Audio = audio.Checked,
                Power = power.Checked, Saver = saver.Checked, Wallpaper = wallpaper.Checked,
                RefreshRate = (int)refreshRate.Value, BrightnessPercent = (int)brightnessPercent.Value,
                VolumePercent = (int)volumePercent.Value, SaverPercent = (int)saverPercent.Value,
                PowerMode = ProfileSettings.PowerModes[powerMode.SelectedIndex]
            };
            try
            {
                settings.Save(path);
                SavedSettings = settings;
                HasUnsavedChanges = false;
                save.Enabled = false;
                message.Text = UiText.Get("SettingsSaved");
            }
            catch { message.Text = UiText.Get("SettingsSaveFailed"); }
        }
    }
}
