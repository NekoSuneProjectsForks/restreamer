########################################################################
# This bundles CORE and UI into a single image, building both from
# source instead of pulling prebuilt datarhei/restreamer-ui and
# datarhei/base:alpine-core images. FFmpeg itself is still pulled from
# datarhei/base - it isn't one of this project's own repos, and building
# it from source is a separate, much larger undertaking.
#
# Override CORE_REPO/CORE_REF and UI_REPO/UI_REF to build from a
# different fork or branch, e.g.:
#   docker build --build-arg CORE_REF=my-branch .
########################################################################

ARG CORE_REPO=https://github.com/nekosuneprojectsforks/core.git
ARG CORE_REF=main
ARG UI_REPO=https://github.com/nekosuneprojectsforks/restreamer-ui.git
ARG UI_REF=main

ARG GOLANG_IMAGE=golang:1.24-alpine3.22
ARG NODE_IMAGE=node:21-alpine3.20
ARG FFMPEG_IMAGE=datarhei/base:alpine-ffmpeg-latest

########################################################################
# CORE (Go)
########################################################################
FROM alpine:3.19 AS core-src

ARG CORE_REPO
ARG CORE_REF

RUN apk add --no-cache git
RUN git clone --depth 1 --branch ${CORE_REF} ${CORE_REPO} /src

FROM --platform=$BUILDPLATFORM ${GOLANG_IMAGE} AS core-builder

ARG TARGETOS TARGETARCH TARGETVARIANT
ENV GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=$TARGETVARIANT

RUN apk add --no-cache git make

COPY --from=core-src /src /dist/core

RUN cd /dist/core && \
	make release && \
	make import && \
	make ffmigrate

########################################################################
# UI (React)
########################################################################
FROM alpine:3.19 AS ui-src

ARG UI_REPO
ARG UI_REF

RUN apk add --no-cache git
RUN git clone --depth 1 --branch ${UI_REF} ${UI_REPO} /src

FROM ${NODE_IMAGE} AS ui-builder

ENV PUBLIC_URL="./"

COPY --from=ui-src /src /ui

WORKDIR /ui

RUN yarn install && yarn build

########################################################################
# Bundle
########################################################################
FROM ${FFMPEG_IMAGE}

COPY --from=core-builder /dist/core/core /core/bin/core
COPY --from=core-builder /dist/core/import /core/bin/import
COPY --from=core-builder /dist/core/ffmigrate /core/bin/ffmigrate
COPY --from=core-builder /dist/core/mime.types /core/mime.types
COPY --from=ui-builder /ui/build /core/ui

ADD https://raw.githubusercontent.com/nekosuneprojectsforks/restreamer/2.x/CHANGELOG.md /core/ui/CHANGELOG.md
COPY ./run.sh /core/bin/run.sh
COPY ./ui-root /core/ui-root

RUN mkdir -p /core/config /core/data && \
	chmod +x /core/bin/run.sh /core/bin/core && \
	ffmpeg -buildconf

ENV CORE_CONFIGFILE=/core/config/config.json
ENV CORE_DB_DIR=/core/config
ENV CORE_ROUTER_UI_PATH=/core/ui
ENV CORE_STORAGE_DISK_DIR=/core/data

# WebRTC (WHIP/WHEP) is off by default; enable with CORE_WEBRTC_ENABLE=true.
# ICE_UDP_MUX_PORT is the single UDP port all WHIP/WHEP media/ICE traffic
# uses - open/forward it alongside the usual ports if you enable it. If
# running behind NAT/Docker port-mapping, also set CORE_WEBRTC_NAT1TO1_IPS
# to your publicly reachable host/IP so remote peers know where to send
# media.
ENV CORE_WEBRTC_ENABLE=false
ENV CORE_WEBRTC_ICE_UDP_MUX_PORT=8189

EXPOSE 8080/tcp
EXPOSE 8181/tcp
EXPOSE 1935/tcp
EXPOSE 1936/tcp
EXPOSE 6000/udp
EXPOSE 8189/udp

VOLUME ["/core/data", "/core/config"]
ENTRYPOINT ["/core/bin/run.sh"]
WORKDIR /core
