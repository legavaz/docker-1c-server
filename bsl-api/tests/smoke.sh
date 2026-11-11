#!/usr/bin/env bash
# Смоук-тест сервиса bsl-api (v1.0.2: обязательный user, необязательный ticket).
# Запуск на VM:  bash smoke.sh <token> [port]
# Токен передаётся аргументом и нигде не сохраняется.
set -uo pipefail

TOKEN="${1:?нужен токен}"
PORT="${2:-8080}"
BASE="http://localhost:${PORT}"
AUTH="Authorization: Bearer ${TOKEN}"
TMP="$(mktemp -d)"
SMOKE_USER="smoke-test"

echo "== health"
curl -s "${BASE}/health"; echo

echo "== без токена (ожидаем 401)"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check" \
  -H 'Content-Type: application/json' -d '{"text":"x","user":"x"}'

echo "== текст без user (ожидаем 422)"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check" -H "${AUTH}" \
  -H 'Content-Type: application/json' -d '{"filename":"Модуль.bsl","text":"Процедура А()\nКонецПроцедуры\n"}'

echo "== user из пробелов (ожидаем 422)"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check" -H "${AUTH}" \
  -H 'Content-Type: application/json' -d '{"filename":"Модуль.bsl","text":"x","user":"   "}'

echo "== user длиннее 150 (ожидаем 422)"
LONG_USER="$(printf 'а%.0s' $(seq 1 151))"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check" -H "${AUTH}" \
  -H 'Content-Type: application/json' -d "{\"filename\":\"Модуль.bsl\",\"text\":\"x\",\"user\":\"${LONG_USER}\"}"

echo "== ticket длиннее 50 (ожидаем 422)"
LONG_TICKET="$(printf 'T%.0s' $(seq 1 51))"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check" -H "${AUTH}" \
  -H 'Content-Type: application/json' -d "{\"filename\":\"Модуль.bsl\",\"text\":\"x\",\"user\":\"${SMOKE_USER}\",\"ticket\":\"${LONG_TICKET}\"}"

echo "== текст с user и ticket (ожидаем valid=true: предупреждения не блокируют, поля user/ticket в ответе)"
curl -s -X POST "${BASE}/check" -H "${AUTH}" -H 'Content-Type: application/json' \
  -d "{\"filename\":\"Модуль.bsl\",\"text\":\"Процедура Тест()\n    Если Истина Тогда\n        Сообщить(\\\"x\\\");\n    КонецЕсли\nКонецПроцедуры\n\",\"user\":\"${SMOKE_USER}\",\"ticket\":\"ERP-1234\"}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("valid:", d.get("valid"), "user:", d.get("user"), "ticket:", d.get("ticket"), "ms:", d.get("duration_ms"))'

echo "== файл с user без ticket (ожидаем 200, ticket=None)"
printf 'Процедура Тест()\n    А = 1;\nКонецПроцедуры\n' > "${TMP}/ТестовыйМодуль.bsl"
curl -s -X POST "${BASE}/check/file" -H "${AUTH}" \
  -F "file=@${TMP}/ТестовыйМодуль.bsl" -F "user=${SMOKE_USER}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("valid:", d.get("valid"), "user:", d.get("user"), "ticket:", d.get("ticket"))'

echo "== файл без user (ожидаем 422)"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check/file" -H "${AUTH}" \
  -F "file=@${TMP}/ТестовыйМодуль.bsl"

echo "== неверное расширение (ожидаем 400)"
curl -s -o /dev/null -w "%{http_code}\n" -X POST "${BASE}/check" -H "${AUTH}" \
  -H 'Content-Type: application/json' -d "{\"filename\":\"evil.sh\",\"text\":\"x\",\"user\":\"${SMOKE_USER}\"}"

echo "== статистика и фильтры"
curl -s "${BASE}/api/stats?days=30" -H "${AUTH}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print({k:d[k] for k in ("checks","valid_share","errors","warnings","avg_duration_ms")}); print("by_user:", [(u["key"], u["checks"]) for u in d["by_user"]]); print("by_ticket:", [(t["key"], t["checks"]) for t in d["by_ticket"]])'
curl -s "${BASE}/api/stats?days=30&user=${SMOKE_USER}" -H "${AUTH}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("filter user=smoke-test -> checks:", d["checks"])'
curl -s "${BASE}/api/journal?limit=3&ticket=ERP-1234" -H "${AUTH}" | python3 -c 'import json,sys; [print(r["ts"][:19], r["user"], r["ticket"], r["status"]) for r in json.load(sys.stdin)]'

echo "== UI отдаётся"
curl -s -o /dev/null -w "%{http_code}\n" "${BASE}/ui"

rm -rf "${TMP}"
