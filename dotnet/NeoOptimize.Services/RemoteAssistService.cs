using System;

namespace NeoOptimize.Services;

public sealed record RemoteAssistTicket(string TicketId, string MachineName, DateTimeOffset CreatedAt);

public sealed class RemoteAssistService
{
    public RemoteAssistTicket CreateDraftTicket(string machineName)
    {
        var ticketId = $"neo-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}-{Math.Abs(machineName.GetHashCode()) % 10000:0000}";
        return new RemoteAssistTicket(ticketId, machineName, DateTimeOffset.Now);
    }
}
