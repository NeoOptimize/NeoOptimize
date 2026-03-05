using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class AppSettings
    {
        public string Theme { get; set; } = "System";
        public string Language { get; set; } = "English";
        public bool AutoUpdate { get; set; } = true;
        public string CurrentVersion { get; set; } = "1.0.0";
        public string ClamAvPath { get; set; } = @"C:\Program Files\ClamAV";
        public string Gpt4AllModel { get; set; } = "mistral-7b.gguf";
    }

    public class SettingsService
    {
        private readonly JsonSerializerOptions _jsonOptions = new JsonSerializerOptions
        {
            WriteIndented = true
        };

        private string GetConfigPath()
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return Path.Combine(appData, "NeoOptimize", "config.json");
        }

        public async Task<AppSettings> LoadAsync()
        {
            try
            {
                string path = GetConfigPath();
                if (!File.Exists(path))
                {
                    return new AppSettings();
                }

                await using var stream = File.OpenRead(path);
                var settings = await JsonSerializer.DeserializeAsync<AppSettings>(stream);
                return settings ?? new AppSettings();
            }
            catch
            {
                return new AppSettings();
            }
        }

        public async Task<bool> SaveAsync(AppSettings settings)
        {
            try
            {
                string path = GetConfigPath();
                string? dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrWhiteSpace(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                await using var stream = File.Create(path);
                await JsonSerializer.SerializeAsync(stream, settings, _jsonOptions);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }
}
