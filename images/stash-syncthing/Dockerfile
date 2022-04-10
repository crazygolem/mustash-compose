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
FROM alpine

EXPOSE 8384 22000/tcp 22000/udp 21027/udp

RUN apk --no-cache add \
    ca-certificates \
    su-exec \
    tzdata

COPY --from=upstream /bin/syncthing /bin/entrypoint.sh /bin/

ENV PUID=1000 PGID=1000 HOME=/var/syncthing

HEALTHCHECK --interval=1m --timeout=10s \
  CMD nc -z 127.0.0.1 8384 || exit 1

### such custom ################################################################

ENTRYPOINT ["/bin/entrypoint.sh", "/syncthing-start", "/var/syncthing/config"]

RUN apk --no-cache add \
    bash \
    curl \
    # Provides GNU xargs, which supports the -L option (unlike Busybox')
    findutils \
    jq \
    # I don't want to figure out the hard way why Busybox' sed borks
    sed

COPY ./rootfs /
