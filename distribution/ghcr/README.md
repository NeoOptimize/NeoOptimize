# NeoOptimize GHCR Package

The GitHub Container Registry package stores the NeoOptimize `1.0` Windows
installer and checksum as an OCI package.

```bash
docker pull ghcr.io/neooptimize/neooptimize:1.0
docker run --rm ghcr.io/neooptimize/neooptimize:1.0 --sha256
docker run --rm -v "$PWD:/out" ghcr.io/neooptimize/neooptimize:1.0 --copy /out
```

The package does not run NeoOptimize in Linux. It provides a registry-hosted
installer artifact for distribution, checksum verification, and automation.
