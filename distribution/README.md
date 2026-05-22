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
| `NeoOptimize.exe` | `70864f39c4d111c4071061381f0127f30afa406fda95f6e02ad52293635937af` |
| `NeoOptimize-portable.zip` | `3fa2c27b3c63a9413b110477af161f5d04e3bf379c102c36aab8bf385cfaf6f4` |

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

