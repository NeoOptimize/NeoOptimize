# Package Manager Distribution

NeoOptimize prepares three public Windows distribution paths:

| Channel | Package | Notes |
| --- | --- | --- |
| WinGet | `ZenthralixLab.NeoOptimize` | Uses the public NSIS installer. |
| Chocolatey | `neooptimize` | Uses the public NSIS installer with SHA-256 verification. |
| Scoop | `neooptimize` | Planned for a later user-space package. |

The current release is `1.0.3`.

## Release Assets

| Asset | SHA-256 |
| --- | --- |
| `NeoOptimize.exe` | `3667a2cb5ff7dfa6aed7ac7a131b6997ffb764fda3a5f4e6bfdb81bcc90620cc` |

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

Scoop should use a later user-space package, not the admin installer. This keeps
the Scoop package aligned with portable package expectations.

Suggested publication path:

1. Produce and sign a user-space package after the installer release is stable.
2. Update `distribution/scoop/neooptimize.json` with the final URL and SHA-256.
3. Test with `scoop install ./neooptimize.json`.
4. Submit to a community bucket after the package has stable download history.
