#!/usr/bin/env bash
# Аудит хранения: есть ли текст кода в журнале, логах контейнера и временных каталогах (запускать на VM).
set -uo pipefail
TOKEN="$(cat "$(dirname "$0")/../.token")"
MARK="AUDITMARK$(date +%s)ZZ"
BODY="{\"filename\":\"Аудит.bsl\",\"user\":\"audit\",\"text\":\"Процедура ${MARK}()\\n    Массив = Новый Массив;\\nКонецПроцедуры\\n\"}"
curl -s -o /dev/null -w "check: HTTP %{http_code}\n" -X POST http://localhost:8080/check \
  -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/json' -d "${BODY}"

echo "== схема журнала"
docker exec bsl-api python3 -c "import sqlite3; c=sqlite3.connect('/data/journal.db'); print([r[1] for r in c.execute('PRAGMA table_info(checks)')])"

echo "== метка в записях журнала (ожидаем 0)"
docker exec bsl-api python3 -c "import sqlite3; c=sqlite3.connect('/data/journal.db'); print(sum(1 for row in c.execute('SELECT * FROM checks') if any('${MARK}' in str(v) for v in row)))"

echo "== пример записи журнала"
docker exec bsl-api python3 -c "import sqlite3; c=sqlite3.connect('/data/journal.db'); c.row_factory=sqlite3.Row; r=c.execute('SELECT * FROM checks ORDER BY id DESC LIMIT 1').fetchone(); print(dict(r))"

echo "== метка в логах контейнера (ожидаем 0)"
docker logs bsl-api 2>&1 | grep -c "${MARK}" || true

echo "== метка во временных каталогах анализа (ожидаем 0)"
docker exec bsl-api sh -c "grep -rl '${MARK}' /tmp/bsl 2>/dev/null | wc -l"

echo "== метка в файлах данных (ожидаем 0)"
docker exec bsl-api sh -c "grep -rl '${MARK}' /data 2>/dev/null | wc -l"
