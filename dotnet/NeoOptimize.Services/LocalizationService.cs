using System.Collections.Generic;

namespace NeoOptimize.Services;

public sealed class LocalizationService
{
    private readonly Dictionary<string, Dictionary<string, string>> _messages = new()
    {
        ["health.optimal"] = new Dictionary<string, string>
        {
            ["English"] = "Optimal",
            ["Indonesian"] = "Optimal"
        },
        ["health.warning"] = new Dictionary<string, string>
        {
            ["English"] = "Needs Attention",
            ["Indonesian"] = "Perlu Perhatian"
        },
        ["health.critical"] = new Dictionary<string, string>
        {
            ["English"] = "Critical",
            ["Indonesian"] = "Kritis"
        }
    };

    public string Translate(string language, string key)
    {
        if (_messages.TryGetValue(key, out var map) &&
            map.TryGetValue(language, out var translated))
        {
            return translated;
        }

        return key;
    }
}
