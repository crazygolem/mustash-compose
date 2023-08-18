ARG syncthing_version

### upstream ###################################################################

# Adapted from syncthing/syncthing's Dockerfile [1].
# Basically we want the same thing as upstream, but without a bunch of stuff we
# are never going to use, e.g. the "home" volume declaration (it forces the
# creation of a named volume we don't care about just to avoid polluting the
# namespace with anonymous volumes), or the entrypoint as we'll use our own
# custom one.
#
# [1]: https://github.com/syncthing/syncthing/blob/main/Dockerfile

FROM syncthing/syncthing:${syncthing_version} AS upstream
FROM alpine:latest

EXPOSE 8384 22000/tcp 22000/udp 21027/udp

RUN apk --no-cache add \
    ca-certificates \
    curl \
    libcap \
    su-exec \
    tzdata

COPY --from=upstream \
    /bin/syncthing /bin/entrypoint.sh /bin/

ENV PUID=1000 PGID=1000 HOME=/var/syncthing

### such custom ################################################################

ENTRYPOINT ["/bin/entrypoint.sh", "/syncthing-start", "/var/syncthing/config"]

# TODO: revert retries and interval to upstream values once --start-interval
#       gets supported on my server:
#       → dockerfile syntax 1.6
#       → buildkit 0.12.0
#       → docker engine 25.0.0
#       → compose https://github.com/docker/compose/issues/10830
HEALTHCHECK --start-period=30s --retries=12 --interval=10s --timeout=5s \
    CMD curl -fkLsS -m 2 127.0.0.1:8384/rest/noauth/health | grep -o --color=never OK || exit 1

RUN apk --no-cache add \
    bash \
    # Provides GNU xargs, which supports the -L option (unlike Busybox')
    findutils \
    jq

COPY ./rootfs /
