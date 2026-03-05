using NeoOptimize.UI.ViewModels;
using Xunit;
using System.Linq;

public class CleanerViewModelTests
{
    [Fact]
    public void UpdateFromEngineJson_AddsCategoryAndProgress()
    {
        var vm = new CleanerViewModel();
        string json = "{\"module\":\"cleaner\",\"category\":\"temp\",\"progress\":42,\"message\":\"scanning\"}";
        vm.UpdateFromEngineJson(json);

        var cat = vm.Categories.FirstOrDefault(c => c.Name == "temp");
        Assert.NotNull(cat);
        Assert.Equal(42, cat.Progress);
        Assert.Equal(1, vm.Logs.Count);
    }
}
