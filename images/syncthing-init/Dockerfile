ARG syncthing_version

FROM syncthing/syncthing:${syncthing_version}

ENV STGUIADDRESS=
ENTRYPOINT ["/bin/entrypoint.sh", "/st-init", "/var/syncthing/config"]

RUN apk --no-cache add \
    bash \
    # Provides GNU xargs, which supports the -L option (unlike Busybox')
    findutils

COPY ./rootfs /
