#!/usr/bin/env bash
# Проверка: помогает ли постоянный кэш BSL LS (запускать на VM).
set -uo pipefail
TOKEN="$(cat /tmp/bsl-test-token)"
docker rm -f bsl-api-test >/dev/null 2>&1 || true
docker run -d --name bsl-api-test -p 8080:8080 \
  -e BSL_SERVICE_TOKEN="${TOKEN}" \
  -v /home/kali/bsl-docker/config:/config:ro \
  -v /home/kali/bsl-platform/bin:/opt/1c/bin:ro \
  -v bsl-data-test:/data \
  -v bsl-cache-test:/home/bsl/.bsl-language-server \
  bsl-api:1.0.0 >/dev/null
sleep 15
for i in 1 2 3; do
  curl -s -o /dev/null -w "cached check #${i}: %{time_total}s HTTP %{http_code}\n" \
    -X POST "http://localhost:8080/check" -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"filename":"Модуль.bsl","text":"Процедура А()\n    Б = 1;\nКонецПроцедуры\n"}'
done
docker exec bsl-api-test sh -c 'du -sh /home/bsl/.bsl-language-server 2>/dev/null; ls /home/bsl/.bsl-language-server 2>/dev/null | head'
