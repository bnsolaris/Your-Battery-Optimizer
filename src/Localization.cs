using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace BatteryOptimizer
{
    internal static class UiText
    {
        internal static readonly string[] Codes = { "en", "tr", "ru", "es" };
        internal static readonly string[] Names = { "English", "Türkçe", "Русский", "Español" };
        internal static string Language { get; private set; }
        private static Dictionary<string, Dictionary<string, string>> messages;

        internal static string Resolve(string language)
        {
            if (!string.IsNullOrWhiteSpace(language))
            {
                string code = language.Trim().Split('-')[0].ToLowerInvariant();
                if (Array.IndexOf(Codes, code) >= 0) return code;
            }
            return "en";
        }

        internal static string InstalledLanguage()
        {
            using (var key = Registry.CurrentUser.OpenSubKey(Product.Registration))
            {
                string saved = key == null ? null : key.GetValue("Language") as string;
                return Resolve(saved ?? CultureInfo.CurrentUICulture.Name);
            }
        }

        internal static void Load(string language)
        {
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(Product.TranslationsFile))
            {
                if (stream == null) throw new FileNotFoundException("Missing " + Product.TranslationsFile);
                using (var reader = new StreamReader(stream, Encoding.UTF8))
                    LoadJson(reader.ReadToEnd(), language);
            }
        }

        internal static void LoadJson(string json, string language)
        {
            messages = new JavaScriptSerializer().Deserialize<Dictionary<string, Dictionary<string, string>>>(json);
            Select(language);
        }

        internal static void Select(string language)
        {
            Language = Resolve(language);
        }

        internal static string Get(string key, params object[] arguments)
        {
            Dictionary<string, string> translations;
            string value;
            if (messages == null || !messages.TryGetValue(key, out translations)) return key;
            if (!translations.TryGetValue(Language, out value)) value = translations["en"];
            return arguments.Length == 0 ? value : string.Format(CultureInfo.CurrentCulture, value, arguments);
        }
    }
}
