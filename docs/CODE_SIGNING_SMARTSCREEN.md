# NeoOptimize Code Signing & SmartScreen

## Current Lab Signing

The lab installer can be signed with a local self-signed Authenticode certificate:

- certificate: `certs/codesign.pfx`
- password file: `certs/lab-codesign.pass`
- generator: `scripts/Create-LabCodeSigningCert.sh`

This is useful for validating the signing pipeline and timestamping behavior.

Important: a self-signed certificate does **not** create Microsoft SmartScreen
reputation and should not be used for public releases.

## Production Requirement

To reduce SmartScreen warnings for real users, NeoOptimize needs a trusted
code-signing certificate:

- OV code-signing certificate: acceptable for normal releases, but reputation may
  need time and downloads to build.
- EV code-signing certificate: stronger identity verification and usually the
  best path for new software reputation.

The release file must also be timestamped, so old installers remain valid after
the certificate expires.

## Build With A Production Certificate

Place the trusted `.pfx` outside the repository or in `certs/codesign.pfx`.
Do not commit it.

Run:

```bash
export CODESIGN_PFX=/absolute/path/to/codesign.pfx
export CODESIGN_PASS='certificate-password'
export CODESIGN_NAME='Zenthralix Lab'
export CODESIGN_URL='https://neooptimize.com'
export CODESIGN_TIMESTAMP_URL='http://timestamp.digicert.com'

OPTIMIZER_EXE=/absolute/path/to/NeoOptimize.exe \
AGENT_EXE=/absolute/path/to/NeoOptimize.Agent.exe \
bash installer/client/build.sh
```

The build script signs:

- `NeoOptimize.Agent.exe`
- final installer `release/NeoOptimize.exe`

## Verify Signature

Linux:

```bash
osslsigncode verify -in release/NeoOptimize.exe
```

Windows:

```powershell
Get-AuthenticodeSignature .\NeoOptimize.exe | Format-List *
```

Expected production status on Windows:

```text
Status: Valid
```

## SmartScreen Reality

Code signing proves publisher identity and file integrity. SmartScreen also uses
reputation signals. A new certificate or rarely downloaded binary can still show
a warning until reputation is established.

To build reputation cleanly:

- use a trusted OV/EV certificate
- keep the same certificate across releases
- timestamp every build
- publish from the same official domain
- avoid frequently changing filenames and unsigned binaries
- do not distribute test builds as public releases
