#!/usr/bin/env bash
# Поднимает тестовый контейнер bsl-api со случайным токеном, пишет токен в /tmp/bsl-test-token (chmod 600).
set -euo pipefail
TOKEN="$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
umask 077
printf '%s\n' "${TOKEN}" > /tmp/bsl-test-token
docker rm -f bsl-api-test >/dev/null 2>&1 || true
docker run -d --name bsl-api-test -p 8080:8080 \
  -e BSL_SERVICE_TOKEN="${TOKEN}" \
  -v /home/kali/bsl-docker/config:/config:ro \
  -v /home/kali/bsl-platform/bin:/opt/1c/bin:ro \
  -v bsl-data-test:/data \
  bsl-api:1.0.0 >/dev/null
echo "started; token saved to /tmp/bsl-test-token"
