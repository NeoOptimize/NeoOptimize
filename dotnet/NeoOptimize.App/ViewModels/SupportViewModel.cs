namespace NeoOptimize.App.ViewModels;

public sealed class SupportViewModel : ViewModelBase
{
    private string _draftTicketId = "-";

    public string DeveloperName => "Sigit profesional IT";
    public string WhatsApp => "087889911030";
    public string Email => "neooptimizeofficial@gmail.com";
    public string BuyMeACoffee => "https://buymeacoffee.com/nol.eight";
    public string Saweria => "https://saweria.co/dtechtive";
    public string Dana => "https://ik.imagekit.io/dtechtive/Dana";

    public string DraftTicketId
    {
        get => _draftTicketId;
        set => SetProperty(ref _draftTicketId, value);
    }
}
