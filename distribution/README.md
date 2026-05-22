# Package Manager Distribution

NeoOptimize prepares three public Windows distribution paths:

| Channel | Package | Notes |
| --- | --- | --- |
| WinGet | `ZenthralixLab.NeoOptimize` | Uses the public NSIS installer. |
| Chocolatey | `neooptimize` | Uses the public NSIS installer with SHA-256 verification. |
| Scoop | `neooptimize` | Uses the portable ZIP package. |

The current release is `1.0.0`.

## Release Assets

| Asset | SHA-256 |
| --- | --- |
| `NeoOptimize.exe` | `8657d576ac92563415ab8ee9aa971821864928a3b74b4c0b66b100d3daf45471` |
| `NeoOptimize-portable.zip` | `5c5770c1869944b9239a7c682f6583618a7e8c658680eaf3ed3dd53deea5a807` |

## WinGet

Manifest:

```text
distribution/winget/ZenthralixLab.NeoOptimize.yaml
```

Submission path:

1. Validate the manifest with WinGet tooling.
2. Submit it to `microsoft/winget-pkgs`.
3. Keep the installer URL and SHA-256 aligned with GitHub Releases.

## Chocolatey

Package files:

```text
distribution/chocolatey/neooptimize.nuspec
distribution/chocolatey/tools/chocolateyinstall.ps1
distribution/chocolatey/tools/chocolateyuninstall.ps1
```

Local package build:

```powershell
choco pack .\distribution\chocolatey\neooptimize.nuspec
```

Chocolatey community submission requires a Chocolatey account and API key.

## Scoop

Manifest:

```text
distribution/scoop/neooptimize.json
```

Scoop uses `NeoOptimize-portable.zip`, not the admin installer. This keeps the
Scoop package aligned with portable package expectations.

Suggested publication path:

1. Add `neooptimize.json` to a maintained bucket.
2. Test with `scoop install ./neooptimize.json`.
3. Submit to a community bucket after the package has stable download history.
