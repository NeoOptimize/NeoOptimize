# NeoOptimize Release Checklist (v1.0)

## 1. Final Validation

- [x] `dotnet build .\dotnet\NeoOptimize.slnx`
- [x] `dotnet test .\dotnet\NeoOptimize.slnx --no-build`
- [x] Build installer MSI:
  - `.\dotnet\scripts\package-installers.ps1 -Variant both -ProductVersion 1.0.0`
- [x] MIT license agreement integrated in installer UI.

## 2. Artifact Verification

- [x] Core-only MSI generated:
  - `dotnet\out\installers\NeoOptimize-CoreOnly.msi`
- [x] Core+AI MSI generated:
  - `dotnet\out\installers\NeoOptimize-CorePlusAI.msi`

## 3. Git Finalization

- [ ] Ensure working tree is clean after commit.
- [ ] Push branch:
  - `git push origin main`

## 4. Tag v1.0

- [ ] Create annotated tag:
  - `git tag -a v1.0 -m "NeoOptimize v1.0"`
- [ ] Push tag:
  - `git push origin v1.0`

## 5. GitHub Release

- [ ] Create release from tag `v1.0`.
- [ ] Upload release artifacts:
  - `NeoOptimize-CoreOnly.msi`
  - `NeoOptimize-CorePlusAI.msi`
- [ ] Release notes include:
  - Windows offline WPF architecture.
  - UI modernization + MiniTray panel.
  - MIT license agreement during install.
  - AI advisor remains advisor-only (no direct system mutation).
