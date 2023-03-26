FROM ubuntu:xenial

ENV GOSU_VERSION 1.7
RUN apt-get -qq update \
  && apt-get -qq install --yes --no-install-recommends ca-certificates wget locales \
  && `#----- Install the dependencies -----` \
  && apt-get -qq install --yes --no-install-recommends fontconfig imagemagick \
  && `#----- Deal with ttf-mscorefonts-installer -----` \
  && apt-get -qq install --yes --no-install-recommends xfonts-utils cabextract \
  && wget --quiet --output-document /tmp/ttf-mscorefonts-installer_3.6_all.deb http://ftp.us.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.6_all.deb \
  && dpkg --install /tmp/ttf-mscorefonts-installer_3.6_all.deb 2> /dev/null \
  && rm /tmp/ttf-mscorefonts-installer_3.6_all.deb \
  && `#----- Install gosu -----` \
  && wget --quiet --output-document /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
  && chmod +x /usr/local/bin/gosu \
  && gosu nobody true

RUN localedef --inputfile ru_RU --force --charmap UTF-8 --alias-file /usr/share/locale/locale.alias ru_RU.UTF-8
ENV LANG ru_RU.utf8

ENV SERVER_VERSION 20.1996

# setup-full-8.3.20.1996-x86_64.run 
ADD setup-full-8.3.${SERVER_VERSION}-x86_64.run /tmp/
RUN chmod +x /tmp/setup-full-8.3.${SERVER_VERSION}-x86_64.run \
&& /tmp/setup-full-8.3.${SERVER_VERSION}-x86_64.run --mode unattended --disable-components client_full --enable-components server,ws,server_admin,config_storage_server,liberica_jre

RUN ln -s /opt/1cv8/x86_64/8.3.${SERVER_VERSION}/srv1cv83 /etc/init.d/srv1cv83 \
&& ln -s /opt/1cv8/x86_64/8.3.${SERVER_VERSION}/srv1cv83.conf /etc/default/srv1cv83 \
&& update-rc.d srv1cv83 defaults

RUN rm /tmp/*.* \
  && mkdir --parents /var/log/1C /home/usr1cv8/.1cv8/1C/1cv8/conf \
  && chown --recursive usr1cv8:grp1cv8 /var/log/1C /home/usr1cv8

COPY container/docker-entrypoint.sh /
COPY container/logcfg.xml /home/usr1cv8/.1cv8/1C/1cv8/conf

ENTRYPOINT ["/docker-entrypoint.sh"]

VOLUME /home/usr1cv8
VOLUME /var/log/1C

EXPOSE 1540-1541 1560-1591