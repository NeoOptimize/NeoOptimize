using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System;

namespace NeoOptimize.App.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private string _experienceMode = "Advanced";
    private string _theme = "Dark";
    private string _language = "Indonesian";
    private string _aiProvider = "Off";
    private string _gpt4allEndpoint = string.Empty;
    private string _gpt4allCliPath = string.Empty;
    private int _gpt4allTimeoutSeconds = 8;

    public IReadOnlyList<string> ExperienceModes { get; } = new[] { "Simple", "Advanced" };
    public IReadOnlyList<string> Themes { get; } = new[] { "Dark", "Light" };
    public IReadOnlyList<string> Languages { get; } = new[] { "Indonesian", "English" };
    public IReadOnlyList<string> AiProviders { get; } = new[] { "Off", "GPT4All_CLI", "GPT4All_HTTP" };

    public string ExperienceMode
    {
        get => _experienceMode;
        set => SetProperty(ref _experienceMode, value);
    }

    public string Theme
    {
        get => _theme;
        set => SetProperty(ref _theme, value);
    }

    public string Language
    {
        get => _language;
        set => SetProperty(ref _language, value);
    }

    public string AiProvider
    {
        get => _aiProvider;
        set => SetProperty(ref _aiProvider, value);
    }

    public string Gpt4AllEndpoint
    {
        get => _gpt4allEndpoint;
        set => SetProperty(ref _gpt4allEndpoint, value);
    }

    public string Gpt4AllCliPath
    {
        get => _gpt4allCliPath;
        set => SetProperty(ref _gpt4allCliPath, value);
    }

    public int Gpt4AllTimeoutSeconds
    {
        get => _gpt4allTimeoutSeconds;
        set => SetProperty(ref _gpt4allTimeoutSeconds, value);
    }

    private static string GetSettingsPath()
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NeoOptimize", "settings.json");

    public static SettingsViewModel Load()
    {
        try
        {
            var path = GetSettingsPath();
            if (!File.Exists(path)) return new SettingsViewModel();
            var json = File.ReadAllText(path);
            var doc = JsonSerializer.Deserialize<SettingsViewModel>(json);
            return doc ?? new SettingsViewModel();
        }
        catch
        {
            return new SettingsViewModel();
        }
    }

    public void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(GetSettingsPath())!;
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            var json = JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(GetSettingsPath(), json);
        }
        catch
        {
        }
    }
}
