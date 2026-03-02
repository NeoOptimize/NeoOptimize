# NeoOptimize .NET Scaffold

Windows-first scaffold for gradual migration from Electron to native WPF.

## Projects

- `NeoOptimize.App` (WPF UI + MVVM)
- `NeoOptimize.Core` (Cleaner/Optimizer/SystemTools/Security/Log/Scheduler/Tray)
- `NeoOptimize.Services` (Update, Localization, Remote Assist)
- `NeoOptimize.AIAdvisor` (RuleBased + Ollama + GPT4All adapters)
- `NeoOptimize.Tests` (xUnit unit tests)
- `NeoOptimize.Installer` (WiX v4 template, optional AI feature)

## Run

```powershell
dotnet build .\NeoOptimize.slnx
dotnet test .\NeoOptimize.slnx
dotnet run --project .\NeoOptimize.App\NeoOptimize.App.csproj
```

## AI Advisor Notes

- AI is advisor-only by design.
- System execution remains in native core engine.
- App manifest requests `requireAdministrator` for native system operations.
- `CompositeAiAdvisor` tries:
  1. `OllamaAiAdvisor`
  2. `Gpt4AllAiAdvisor`
  3. fallback `RuleBasedAiAdvisor`

## Local AI Runtime Configuration

### Ollama

Optional env vars:

- `NEO_OLLAMA_ENDPOINT` (default: `http://127.0.0.1:11434/api/generate`)
- `NEO_OLLAMA_MODEL` (default: `llama3.1:8b`)

### GPT4All

`Gpt4AllAiAdvisor` tries local HTTP first, then optional CLI bridge.

Optional env vars:

- `NEO_GPT4ALL_ENDPOINT` (default: `http://127.0.0.1:4891/v1/chat/completions`)
- `NEO_GPT4ALL_MODEL` (default: `gpt4all`)
- `NEO_GPT4ALL_CLI` (full path to CLI executable)
- `NEO_GPT4ALL_CLI_ARGS` (default: `--model {model} --prompt {prompt}`)

If both adapters are unavailable, app falls back to `RuleBasedAiAdvisor`.
