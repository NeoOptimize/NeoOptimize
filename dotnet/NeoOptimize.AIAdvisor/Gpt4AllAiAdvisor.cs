using System;
using System.Threading;
using System.Threading.Tasks;
using NeoOptimize.AIAdvisor.Models;

namespace NeoOptimize.AIAdvisor;

public sealed class Gpt4AllAiAdvisor : IAiAdvisor
{
    public Task<AiAdviceResponse> GetAdviceAsync(AiAdviceRequest request, CancellationToken cancellationToken)
    {
        var message = "GPT4All adapter belum dihubungkan ke runtime lokal. " +
                      "Set path model dan binding native untuk produksi.";

        return Task.FromResult(new AiAdviceResponse(
            Success: false,
            Provider: "GPT4All",
            Recommendation: message,
            GeneratedAt: DateTimeOffset.Now));
    }
}
