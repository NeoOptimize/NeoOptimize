using System.Windows;
using NeoOptimize.AIAdvisor;
using NeoOptimize.App.ViewModels;
using NeoOptimize.Core;
using NeoOptimize.Services;

namespace NeoOptimize.App;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        var aiAdvisor = new CompositeAiAdvisor(
            new RuleBasedAiAdvisor(),
            new OllamaAiAdvisor(),
            new Gpt4AllAiAdvisor());

        DataContext = new MainWindowViewModel(
            new CleanerEngine(),
            new OptimizerEngine(),
            new SystemToolsEngine(),
            new SecurityEngine(),
            new LogManager(),
            new Scheduler(),
            new TrayService(),
            new UpdateService(),
            new LocalizationService(),
            new RemoteAssistService(),
            aiAdvisor);
    }
}
