FROM ubuntu:22.04

LABEL org.opencontainers.image.title="1C:Enterprise Server 8.3.27.2342" \
      org.opencontainers.image.description="1C:Enterprise 8.3 server (ragent / rmngr / rph) on Ubuntu 22.04"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=ru_RU.UTF-8 \
    LANGUAGE=ru_RU:ru \
    LC_ALL=ru_RU.UTF-8 \
    V8_VERSION=8.3.27.2342

RUN apt-get update \
 && apt-get install -y --no-install-recommends locales util-linux \
 && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8 \
 && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

COPY dist/ /tmp/dist/

RUN apt-get update \
 && apt-get install -y --no-install-recommends /tmp/dist/*.deb \
 && rm -rf /tmp/dist /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/1c-entrypoint.sh
RUN chmod 0755 /usr/local/bin/1c-entrypoint.sh \
 && mkdir -p /home/usr1cv8/.1cv8/1C/1cv8 /var/log/1c \
 && chown -R usr1cv8:grp1cv8 /home/usr1cv8 /var/log/1c

EXPOSE 1540 1541 1545 1560-1591
VOLUME ["/home/usr1cv8/.1cv8", "/var/log/1c"]

ENTRYPOINT ["/usr/local/bin/1c-entrypoint.sh"]
