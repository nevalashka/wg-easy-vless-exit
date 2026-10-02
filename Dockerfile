# Выходной сервер: Xray VLESS + REALITY
# Сборка: DOCKER_BUILDKIT=1 docker build --no-cache -t nevalashka/vless-reality-exit:1.0 .
ARG XRAY_VERSION=v26.9.30

FROM alpine:3.22
ARG XRAY_VERSION
ARG TARGETARCH

RUN set -eux; \
    apk add --no-cache bash curl ca-certificates; \
    case "${TARGETARCH:-amd64}" in \
      amd64) XRAY_ARCH=64 ;; \
      arm64) XRAY_ARCH=arm64-v8a ;; \
      *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    apk add --no-cache --virtual .fetch unzip; \
    curl -fsSLo /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"; \
    mkdir -p /usr/local/share/xray; \
    unzip -q /tmp/xray.zip xray geoip.dat geosite.dat -d /usr/local/share/xray; \
    mv /usr/local/share/xray/xray /usr/local/bin/xray; \
    chmod +x /usr/local/bin/xray; \
    rm -f /tmp/xray.zip; \
    apk del .fetch; \
    xray version

ENV XRAY_LOCATION_ASSET=/usr/local/share/xray

COPY entrypoint.sh healthcheck.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
