#!/usr/bin/env bash
# Проверка: UnknownMember ловит несуществующий метод платформы через сервис (запускать на VM).
set -uo pipefail
TOKEN="$(cat "$(dirname "$0")/../.token")"
BODY='{"filename":"Правила.bsl","user":"verify-rules","text":"Процедура Тест()\n    Массив = Новый Массив;\n    Массив.НесуществующийМетод();\n    Результат = СтрНайти();\nКонецПроцедуры\n"}'
curl -s -X POST http://localhost:8080/check -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' -d "${BODY}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("valid:", d["valid"], "summary:", d["summary"], "ms:", d["duration_ms"]); [print(" ", w["code"], w["line"], w["message"]) for w in d["errors"]+d["warnings"]]'
