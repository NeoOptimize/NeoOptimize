using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Windowing;
using NeoOptimize.UI.ViewModels;
using Windows.Graphics;
using WinRT.Interop;

namespace NeoOptimize.UI
{
    public sealed partial class MainWindow : Window
    {
        private readonly MainViewModel _vm;

        public MainWindow()
        {
            this.InitializeComponent();
            _vm = new MainViewModel();
            if (this.Content is FrameworkElement root)
            {
                root.DataContext = _vm;
            }
            TryResizeWindow(1024, 768);
            this.Closed += OnWindowClosed;
        }

        private void OnWindowClosed(object sender, WindowEventArgs args)
        {
            _vm.Dispose();
        }

        private void TryResizeWindow(int width, int height)
        {
            try
            {
                IntPtr hwnd = WindowNative.GetWindowHandle(this);
                var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
                AppWindow appWindow = AppWindow.GetFromWindowId(windowId);
                appWindow.Resize(new SizeInt32(width, height));
            }
            catch
            {
            }
        }
    }
}
