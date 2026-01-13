ARG BASE_IMAGE="eclipse-temurin:25-jre-ubi10-minimal"
ARG DOWNLOADER_IMAGE="voidcube/hytale-downloader:2026.1.9"

FROM ${DOWNLOADER_IMAGE} AS downloader

FROM ${BASE_IMAGE} AS base

ARG IMAGE_VERSION

RUN microdnf install -y unzip jq curl && \
    groupadd -r hytale && useradd -r -g hytale hytale

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

COPY --from=downloader /bin/hytale-downloader /usr/local/bin

USER hytale

WORKDIR /data

ENTRYPOINT [ "docker-entrypoint.sh" ]

VOLUME [ "/data" ]

LABEL org.opencontainers.image.title="Hytale Server Image" \
      org.opencontainers.image.description="Docker image for Hytale server application" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.authors="Petr Václavek petr@vaclavek.cloud" \
      org.opencontainers.image.url="https://github.com/voidcubedotgg/hytale-server-docker" \
      org.opencontainers.image.source="https://github.com/voidcubedotgg/hytale-server-docker" \
      org.opencontainers.image.licenses="MIT"

EXPOSE 5520/udp