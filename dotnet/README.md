# NeoOptimize .NET

Native Windows implementation for NeoOptimize using WPF and .NET 8.

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

## Packaging

Install WiX CLI once:

```powershell
dotnet tool install --global wix --version 4.*
```

Install WiX UI extension once:

```powershell
wix extension add --global WixToolset.UI.wixext/4.0.6
```

Build installers:

```powershell
.\scripts\package-installers.ps1 -Variant both -ProductVersion 1.0.0
```

Outputs:

- `out/installers/NeoOptimize-CoreOnly.msi`
- `out/installers/NeoOptimize-CorePlusAI.msi`

`package-installers.ps1` also verifies and installs `WixToolset.UI.wixext`
if missing/damaged.

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
- `NEO_GPT4ALL_CLI_ARGS` (optional explicit template)

If `NEO_GPT4ALL_CLI_ARGS` is not set, adapter probes common CLI patterns:

- `--model {model} --prompt {prompt}`
- `--model {model} -p {prompt}`
- `-m {model} -p {prompt}`
- `--prompt {prompt}`
- `-p {prompt}`

If both adapters are unavailable, app falls back to `RuleBasedAiAdvisor`.

