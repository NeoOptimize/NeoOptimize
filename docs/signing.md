Code signing — optional (offline-first)

NeoOptimize is intended as an offline Windows app. CI workflows should not require cloud signing by default.

If you want to add automated code signing later, use one of these approaches:

- Local signing on a secure build machine using a PFX file and `signtool` (recommended for offline builds).
  - Keep the PFX off the repo; store it on the build machine and sign during release packaging.
  - Example: `signtool sign /fd SHA256 /a /f "C:\path\to\signing.pfx" /p <password> "NeoOptimize-Setup-1.0.0.exe"`

- Cloud signing (optional): use Azure Key Vault or GitHub Actions with secure secrets. Only enable on release branches and protect secrets. Document the process and access controls.

For now the CI workflow does not perform automatic signing; releasing a signed build should be a conscious manual step or a protected pipeline used by maintainers.
