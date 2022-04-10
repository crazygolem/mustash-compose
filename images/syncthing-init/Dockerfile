ARG syncthing_version

FROM syncthing/syncthing:${syncthing_version}

ENV STGUIADDRESS=
ENTRYPOINT ["/bin/entrypoint.sh", "/st-init", "/var/syncthing/config"]

RUN apk --no-cache add \
    bash \
    curl \
    # Provides GNU xargs, which supports the -L option (unlike Busybox')
    findutils \
    jq \
    # I don't want to figure out the hard way why Busybox' sed borks
    sed

COPY ./rootfs /
