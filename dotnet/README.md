# NeoOptimize .NET Scaffold

Windows-first scaffold for gradual migration from Electron to native WPF.

## Projects

- `NeoOptimize.App` (WPF UI + MVVM)
- `NeoOptimize.Core` (Cleaner/Optimizer/SystemTools/Security/Log/Scheduler/Tray)
- `NeoOptimize.Services` (Update, Localization, Remote Assist)
- `NeoOptimize.AIAdvisor` (RuleBased + Ollama + GPT4All adapters)
- `NeoOptimize.Tests` (xUnit unit tests)
- `NeoOptimize.Installer` (WiX placeholder)

## Run

```powershell
dotnet build .\NeoOptimize.slnx
dotnet test .\NeoOptimize.slnx
dotnet run --project .\NeoOptimize.App\NeoOptimize.App.csproj
```

## AI Advisor Notes

- AI is advisor-only by design.
- System execution remains in native core engine and can be gated by admin checks.
- `CompositeAiAdvisor` tries:
  1. `OllamaAiAdvisor`
  2. `Gpt4AllAiAdvisor`
  3. fallback `RuleBasedAiAdvisor`

