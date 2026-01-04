ARG BASE_IMAGE=""

FROM ${BASE_IMAGE} AS base

RUN useradd hytale && mkdir -p /data

COPY docker-entrypoint.sh /usr/local/bin

WORKDIR /data

USER hytale

ENTRYPOINT [ "docker-entrypoint.sh" ]

VOLUME [ "/data" ]