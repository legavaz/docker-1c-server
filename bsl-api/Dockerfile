# Образ сервиса проверки BSL поверх образа BSL Language Server (Temurin 21 + jar).
# Сборка на VM: сначала собрать bsl-language-server (bsl-server/Dockerfile), затем этот образ.
FROM bsl-language-server:latest

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt

COPY app /opt/bsl-api/app
RUN mkdir -p /data /tmp/bsl \
 && chown -R bsl:bsl /data /tmp/bsl /opt/bsl-api

USER bsl
WORKDIR /opt/bsl-api
ENV BSL_DATA=/data \
    BSL_WORK=/tmp/bsl \
    BSL_CONFIG=/config/.bsl-language-server.json
EXPOSE 8080

ENTRYPOINT ["/opt/venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
