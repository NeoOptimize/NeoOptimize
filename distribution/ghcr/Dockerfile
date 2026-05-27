FROM alpine:3.20

ARG NEOOPTIMIZE_VERSION=1.0
ARG NEOOPTIMIZE_SHA256=
ARG NEOOPTIMIZE_RELEASE_URL=https://github.com/NeoOptimize/NeoOptimize/releases/tag/v1.0

LABEL org.opencontainers.image.title="NeoOptimize"
LABEL org.opencontainers.image.description="NeoOptimize v1.0 Windows installer package with checksum metadata."
LABEL org.opencontainers.image.vendor="Zenthralix Lab"
LABEL org.opencontainers.image.version="${NEOOPTIMIZE_VERSION}"
LABEL org.opencontainers.image.url="${NEOOPTIMIZE_RELEASE_URL}"
LABEL org.opencontainers.image.source="https://github.com/NeoOptimize/NeoOptimize"
LABEL org.opencontainers.image.licenses="MIT"

RUN adduser -D -H -u 10001 neooptimize \
  && mkdir -p /opt/neooptimize \
  && chown -R neooptimize:neooptimize /opt/neooptimize

COPY release/windows/NeoOptimize.exe /opt/neooptimize/NeoOptimize.exe
COPY release/windows/NeoOptimize.exe.sha256 /opt/neooptimize/NeoOptimize.exe.sha256
COPY distribution/ghcr/neooptimize-package /usr/local/bin/neooptimize-package

RUN chmod 0755 /usr/local/bin/neooptimize-package \
  && chmod 0644 /opt/neooptimize/NeoOptimize.exe /opt/neooptimize/NeoOptimize.exe.sha256 \
  && if [ -n "$NEOOPTIMIZE_SHA256" ]; then \
       echo "$NEOOPTIMIZE_SHA256  /opt/neooptimize/NeoOptimize.exe" | sha256sum -c -; \
     fi

USER neooptimize
ENTRYPOINT ["/usr/local/bin/neooptimize-package"]
CMD ["--help"]
