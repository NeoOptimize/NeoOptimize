using System;
using System.Threading;
using System.Threading.Tasks;
using NeoOptimize.AIAdvisor.Models;

namespace NeoOptimize.AIAdvisor;

public sealed class CompositeAiAdvisor : IAiAdvisor
{
    private readonly IAiAdvisor _fallback;
    private readonly IAiAdvisor _primary;
    private readonly IAiAdvisor _secondary;

    public CompositeAiAdvisor(IAiAdvisor fallback, IAiAdvisor primary, IAiAdvisor secondary)
    {
        _fallback = fallback;
        _primary = primary;
        _secondary = secondary;
    }

    public async Task<AiAdviceResponse> GetAdviceAsync(AiAdviceRequest request, CancellationToken cancellationToken)
    {
        try
        {
            var primaryResult = await _primary.GetAdviceAsync(request, cancellationToken).ConfigureAwait(false);
            if (primaryResult.Success) return primaryResult;
        }
        catch (Exception)
        {
        }

        try
        {
            var secondaryResult = await _secondary.GetAdviceAsync(request, cancellationToken).ConfigureAwait(false);
            if (secondaryResult.Success) return secondaryResult;
        }
        catch (Exception)
        {
        }

        return await _fallback.GetAdviceAsync(request, cancellationToken).ConfigureAwait(false);
    }
}
