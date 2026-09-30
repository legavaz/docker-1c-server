FROM eclipse-temurin:21-jre

LABEL org.opencontainers.image.title="BSL Language Server" \
      org.opencontainers.image.description="BSL Language Server batch image (analyze/format) for 1C:Enterprise sources"

RUN useradd -m bsl
RUN mkdir -p /opt/bsl /work /reports /config \
 && chown -R bsl:bsl /work /reports /config /opt/bsl

COPY dist/bsl-language-server.jar /opt/bsl/bsl-language-server.jar

WORKDIR /work
USER bsl

ENTRYPOINT ["java", "-XX:+UseSerialGC", "-Xms256m", "-Xmx4g", "-jar", "/opt/bsl/bsl-language-server.jar"]
