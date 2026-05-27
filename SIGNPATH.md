# SignPath Code Signing

NeoOptimize plans to use SignPath for public freeware/open-source code signing.

## Why SignPath

SignPath is a good fit for freeware/open-source distribution because signing can
be tied to a trusted build pipeline instead of a private developer machine. This
is cleaner than signing a manually copied binary.

## Important Requirements

The public repository must contain the NeoOptimize application source and installer
build scripts needed to produce `NeoOptimize.exe`.

The repository must not publish private infrastructure, credentials, tokens, or
lab-only operational files. Only the public NeoOptimize application source, installer
recipe, assets, module scripts, and documentation should be included.

## Code Signing Policy

Free code signing provided by SignPath.io, certificate by SignPath Foundation.

Team roles:

- Committers and reviewers: NeoOptimize maintainers.
- Approvers: Zenthralix-Lab release owners.

Privacy policy:

This program will not transfer information to other networked systems unless
specifically requested by the user or the person installing or operating it.

## Required SignPath Secrets

Set these repository secrets after the SignPath project is approved:

| Secret | Purpose |
| --- | --- |
| `SIGNPATH_API_TOKEN` | API token from SignPath. |
| `SIGNPATH_ORGANIZATION_ID` | SignPath organization identifier. |
| `SIGNPATH_PROJECT_SLUG` | SignPath project slug for NeoOptimize. |
| `SIGNPATH_SIGNING_POLICY_SLUG` | Signing policy slug. |

## Workflow

The workflow is staged at:

```text
.github/workflows/signpath-release.yml
```

It performs:

1. Checkout public NeoOptimize source.
2. Build the unsigned installer in GitHub Actions.
3. Upload the unsigned artifact.
4. Submit the artifact to SignPath.
5. Download the signed artifact.
6. Upload the signed installer and SHA-256 checksum to GitHub Actions artifacts.

## Current Status

The SignPath workflow is prepared but intentionally gated. It will fail with a
clear message until the public repository contains the application build source:

```text
installer/client/build.sh
wrapper/NeoOptimizeUIWrapper/NeoOptimizeUIWrapper.csproj
client/
```

This prevents accidental signing of an opaque binary that was not built from
public source.

## Artifact Configuration

Create a SignPath artifact configuration named:

```text
neooptimize-installer
```

The GitHub workflow uploads a ZIP artifact containing `NeoOptimize.exe` and its
checksum. The artifact configuration should sign the executable inside that ZIP
and enforce file metadata:

- Product name: `NeoOptimize`
- Product version: `1.0`
- Company/publisher metadata: project-maintainer metadata accepted by SignPath
  for the approved project.

Every signing request should be manually approved by a trusted release owner.

## SmartScreen Note

Code signing improves trust and integrity, but it does not instantly guarantee
Microsoft SmartScreen reputation. Reputation still builds over time through
consistent signed releases and user download history.
