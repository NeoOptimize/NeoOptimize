using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace NeoOptimize.Agent.Security;

public class RsaVerifier
{
    private readonly RSA _rsa;

    public RsaVerifier(string publicKeyBase64)
    {
        _rsa = RSA.Create();

        // Strip PEM headers if they exist
        var base64 = publicKeyBase64
            .Replace("-----BEGIN PUBLIC KEY-----", "")
            .Replace("-----END PUBLIC KEY-----", "");

        // Strip ALL whitespaces
        base64 = System.Text.RegularExpressions.Regex.Replace(base64, @"\s+", "");

        // Add padding if needed
        int mod4 = base64.Length % 4;
        if (mod4 > 0)
        {
            base64 += new string('=', 4 - mod4);
        }

        _rsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(base64), out _);
    }

    public bool VerifyCommand(string cmdId, string cmdType, Dictionary<string, object>? args, string signatureBase64)
    {
        try
        {
            var payload = CanonicalPayload(cmdId, cmdType, args);
            var payloadBytes = Encoding.UTF8.GetBytes(payload);
            var signatureBytes = Convert.FromBase64String(signatureBase64);

            return _rsa.VerifyData(
                payloadBytes,
                signatureBytes,
                HashAlgorithmName.SHA256,
                RSASignaturePadding.Pkcs1
            );
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Security] Signature verification failed: {ex.Message}");
            return false;
        }
    }

    private string CanonicalPayload(string cmdId, string cmdType, Dictionary<string, object>? args)
    {
        var sortedArgs = SortDictionary(args ?? new Dictionary<string, object>());
        // Serialize with no formatting to match JS exactly
        var jsonArgs = JsonSerializer.Serialize(sortedArgs, new JsonSerializerOptions
        {
            WriteIndented = false,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        });
        return $"{cmdId}|{cmdType}|{jsonArgs}";
    }

    private SortedDictionary<string, object?> SortDictionary(IDictionary<string, object> dict)
    {
        var sorted = new SortedDictionary<string, object?>(StringComparer.Ordinal);
        foreach (var kvp in dict)
        {
            if (kvp.Value is JsonElement element)
            {
                sorted[kvp.Key] = NormalizeJsonElement(element);
            }
            else
            {
                sorted[kvp.Key] = kvp.Value;
            }
        }
        return sorted;
    }

    private object? NormalizeJsonElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.Object => SortDictionary(JsonSerializer.Deserialize<Dictionary<string, object>>(element.GetRawText()) ?? new Dictionary<string, object>()),
            JsonValueKind.Array => element.EnumerateArray().Select(NormalizeJsonElement).ToList(),
            JsonValueKind.String => element.GetString(),
            JsonValueKind.Number when element.TryGetInt64(out var longValue) => longValue,
            JsonValueKind.Number when element.TryGetDouble(out var doubleValue) => doubleValue,
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.Null => null,
            _ => element.GetRawText()
        };
    }
}
