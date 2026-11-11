#!/usr/bin/env bash
# Замер времени двух подряд проверок и наличия платформенного контекста (запускать на VM).
TOKEN="$(cat /tmp/bsl-test-token)"
for i in 1 2; do
  curl -s -o /dev/null -w "check #${i}: HTTP %{http_code}, total %{time_total}s\n" \
    -X POST "http://localhost:8080/check" -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"filename":"Модуль.bsl","text":"Процедура А()\n    Б = 1;\nКонецПроцедуры\n"}'
done
echo "--- platform log lines ---"
docker logs bsl-api-test 2>&1 | grep -i -e platform -e hbk -e "BslContextHolder" | tail -n 6
