using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml;
using NeoOptimize.UI.ViewModels;
using NeoOptimize.UI.Services;

namespace NeoOptimize.UI.Views
{
    public sealed partial class CleanerPage : Page
    {
        public CleanerViewModel ViewModel { get; }

        public CleanerPage()
        {
            this.InitializeComponent();
            ViewModel = new CleanerViewModel();
            this.DataContext = ViewModel;
        }

        private async void QuickScan_Click(object sender, RoutedEventArgs e)
        {
            await ViewModel.StartAsync();
        }

        private async void Execute_Click(object sender, RoutedEventArgs e)
        {
            await ViewModel.ExecuteAsync();
        }

        private void CleanSelected_Click(object sender, RoutedEventArgs e)
        {
            // hook for later: open selection UI
        }

        private async void AskAi_Click(object sender, RoutedEventArgs e)
        {
            var text = AiInput.Text ?? string.Empty;
            if (string.IsNullOrWhiteSpace(text)) return;
            try
            {
                var svc = new AiService();
                var resp = await svc.AskAsync(text);
                ViewModel.Logs.Add("AI: " + resp);
            }
            catch (System.Exception ex)
            {
                ViewModel.Logs.Add("AI error: " + ex.Message);
            }
        }
    }
}
