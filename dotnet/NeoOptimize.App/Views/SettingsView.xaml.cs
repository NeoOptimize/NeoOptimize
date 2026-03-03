using System.Windows.Controls;
using System.Windows;
using NeoOptimize.App.ViewModels;

namespace NeoOptimize.App.Views;

public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
    }

    private void OnSaveSettingsClicked(object sender, RoutedEventArgs e)
    {
        if (DataContext is SettingsViewModel vm)
        {
            vm.Save();
        }
        MessageBox.Show("Settings saved.", "NeoOptimize", MessageBoxButton.OK, MessageBoxImage.Information);
    }
}
