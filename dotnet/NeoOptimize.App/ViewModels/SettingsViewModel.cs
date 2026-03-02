using System.Collections.Generic;

namespace NeoOptimize.App.ViewModels;

public sealed class SettingsViewModel : ViewModelBase
{
    private string _experienceMode = "Simple";
    private string _theme = "Dark";
    private string _language = "Indonesian";

    public IReadOnlyList<string> ExperienceModes { get; } = new[] { "Simple", "Advanced" };
    public IReadOnlyList<string> Themes { get; } = new[] { "Dark", "Light" };
    public IReadOnlyList<string> Languages { get; } = new[] { "Indonesian", "English" };

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
}
