# Выходной сервер: Xray VLESS + REALITY
# Сборка: DOCKER_BUILDKIT=1 docker build --no-cache -t nevalashka/vless-reality-exit:0.2 .
ARG XRAY_VERSION=v26.9.30

# ---------- скачивание (curl/unzip остаются только здесь) ----------
FROM alpine:3.22 AS fetch
ARG XRAY_VERSION
ARG TARGETARCH
RUN set -eux; \
    apk add --no-cache curl unzip; \
    case "${TARGETARCH:-amd64}" in \
      amd64) XRAY_ARCH=64 ;; \
      arm64) XRAY_ARCH=arm64-v8a ;; \
      *) echo "unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    curl -fsSLo /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"; \
    mkdir -p /out; \
    unzip -q /tmp/xray.zip xray geoip.dat -d /out; \
    chmod +x /out/xray

# ---------- рантайм: alpine + bash + xray ----------
FROM alpine:3.22
RUN apk upgrade --no-cache && apk add --no-cache bash

COPY --from=fetch /out/xray /usr/local/bin/xray
COPY --from=fetch /out/geoip.dat /usr/local/share/xray/geoip.dat
ENV XRAY_LOCATION_ASSET=/usr/local/share/xray

COPY --chmod=755 entrypoint.sh healthcheck.sh /usr/local/bin/

VOLUME ["/data"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
