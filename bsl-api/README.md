# BSL check service — центральный сервис проверки кода 1С

HTTP-сервис на VM `kali` (по умолчанию `http://192.168.1.51:8080`): принимает модуль 1С
(`.bsl`/`.os`) или текст, проверяет BSL Language Server и возвращает результат:
ошибки и предупреждения отдельно, плюс текстовый отчёт для людей. Ведёт журнал проверок
за 30 дней с разбивкой по пользователям и тикетам Jira, показывает аналитику на веб-странице.

Версия API: **1.0.2**. Все адреса страниц — см. `WEB-PAGES.md`.

```
разработчик (curl/PowerShell)      OpenCode (MCP bsl-check → check_bsl)
          │                                   │
          └──────────────┬────────────────────┘
                         ▼  Authorization: Bearer <токен команды>
              ┌──────────────────────────────────┐
              │ bsl-api  (FastAPI, Portainer)     │
              │  POST /check       текст + user   │
              │  POST /check/file  файл + user    │
              │  GET  /health, /ui, /docs         │
              │  GET  /api/stats, /api/journal    │
              │     └─ java -jar BSL LS 1.0.7     │
              │        + hbk платформы 8.3.27.2342│
              │  SQLite /data/journal.db (30 дней)│
              └──────────────────────────────────┘
```

## Эндпоинты

| Метод | Путь | Токен | Назначение |
|---|---|---|---|
| GET | `/health` | нет | статус и параметры (лимиты, ретенция, адрес Jira) |
| POST | `/check` | да | проверка текста модуля (JSON) |
| POST | `/check/file` | да | проверка файла `.bsl`/`.os` (multipart) |
| GET | `/api/stats` | да | сводка за период, по дням, по пользователям, по тикетам |
| GET | `/api/journal` | да | журнал проверок |
| GET | `/ui` | нет | веб-страница журнала и аналитики |
| GET | `/docs`, `/redoc`, `/openapi.json` | нет | документация API |

Токен передаётся заголовком `Authorization: Bearer <токен>`. Без токена или с неверным — `401`.

## Обязательные и необязательные поля

| Поле | Где | Обязательно | Длина | Примечание |
|---|---|---|---|---|
| `user` | `/check`, `/check/file` | **да** | 1…150 | имя пользователя; пробелы по краям обрезаются, из одних пробелов — `422` |
| `ticket` | `/check`, `/check/file` | нет | до 50 | номер задачи Jira, например `ERP-1234`; пустое значение = не указан |
| `file` | `/check/file` | да | — | файл `.bsl` или `.os` |
| `text`, `filename` | `/check` | `text` да, `filename` нет | `filename` до 120 | по умолчанию `Module.bsl` |

Управляющие символы в `user` и `ticket` запрещены (`422`).

## Формат ответа `/check`, `/check/file`

```json
{
  "valid": true,
  "summary": { "errors": 0, "warnings": 1, "info": 2, "hints": 0 },
  "errors": [],
  "warnings": [
    { "file": "Модуль.bsl", "line": 1, "column": 11, "code": "UnusedLocalMethod",
      "message": "Метод \"Тест\" не вызывается в теле модуля", "severity": "Warning" }
  ],
  "top_codes": [["UnusedLocalMethod", 1]],
  "text": "Ошибок: 0, предупреждений: 1, ...",
  "duration_ms": 21950,
  "files": ["Модуль.bsl"],
  "user": "lega",
  "ticket": "ERP-1234"
}
```

- `valid` — `true`, если нет ошибок уровня **Error**. Предупреждения не блокируют.
- `errors` и `warnings` — отдельные списки; `info` и `hints` только в счётчиках.
- `user` и `ticket` возвращаются так, как записаны в журнал (`ticket` = `null`, если не указан).

## Примеры вызова

curl (текст):
```bash
curl -s -X POST http://192.168.1.51:8080/check \
  -H "Authorization: Bearer $BSL_SERVICE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filename":"Модуль.bsl","text":"Процедура А()\nКонецПроцедуры\n","user":"lega","ticket":"ERP-1234"}'
```

curl (файл):
```bash
curl -s -X POST http://192.168.1.51:8080/check/file \
  -H "Authorization: Bearer $BSL_SERVICE_TOKEN" \
  -F "file=@Модуль.bsl" -F "user=lega" -F "ticket=ERP-1234"
```

PowerShell (файл):
```powershell
$h = @{ Authorization = "Bearer $env:BSL_SERVICE_TOKEN" }
$r = Invoke-RestMethod -Uri http://192.168.1.51:8080/check/file -Method Post -Headers $h `
     -Form @{ file = Get-Item 'E:\rep\...\Модуль.bsl'; user = $env:USERNAME; ticket = 'ERP-1234' }
$r.valid; $r.text
```

Ошибки ввода: без `user` — `422` с указанием поля; `user` длиннее 150 или `ticket` длиннее 50 — `422`.

## Статистика и журнал

Фильтры (необязательные) — у `/api/stats` и `/api/journal`:

```
GET /api/stats?days=30&user=lega&ticket=ERP-1234
GET /api/journal?limit=100&offset=0&user=lega
```

`/api/stats` возвращает:
- `checks`, `valid_share`, `errors`, `warnings`, `avg_duration_ms`;
- `per_day` — по дням;
- `top_codes` — частые диагностики;
- `by_user` — по каждому пользователю: проверок, ошибок, предупреждений, info, hints, среднее время;
- `by_ticket` — то же по тикетам;
- `values` — список известных пользователей и тикетов (для фильтров на `/ui`).

В журнале хранятся: время, IP клиента, источник (text/file), имя файла, размер, статус, счётчики, время проверки, `user`, `ticket`, 5 частых кодов. **Текст кода в журнал не сохраняется.**

Записи, сделанные до версии 1.0.2, не имеют пользователя и тикета: в статистике они не попадают в `by_user`/`by_ticket`, в журнале показываются как «—».

## Ограничения и переменные окружения

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `BSL_SERVICE_TOKEN` | — (обязательна) | общий токен команды |
| `BSL_PORT` | `8080` | внешний порт (в стеке Portainer) |
| `BSL_MAX_BYTES` | `2097152` (2 МБ) | максимальный размер входа |
| `BSL_TIMEOUT_SEC` | `120` | таймаут одной проверки (`504` при превышении) |
| `BSL_RETENTION_DAYS` | `30` | сколько дней хранить журнал |
| `BSL_JIRA_BASE_URL` | пусто | адрес Jira для ссылок в `/ui`, например `https://jira.local/browse/` |

Принимаются только имена `*.bsl` и `*.os` (`400` для других). Пустой вход — `400`.

## Страница `/ui`

- Фильтры «Пользователь» и «Тикет» (выпадающие списки из журнала) и период 7/30 дней.
- Карточки, график по дням, таблицы «По пользователям» и «По тикетам», частые диагностики, последние проверки.
- Если задан `BSL_JIRA_BASE_URL`, тикет в таблице проверок — ссылка.
- Токен хранится в браузере (`localStorage`, ключ `bsl_token`).

## Развёртывание через Portainer (VM kali)

Образы собираются на VM, стек запускает Portainer.

1. Базовый образ BSL LS: `bsl-server/Dockerfile` → `bsl-language-server:latest`.
2. Платформа (hbk) на VM: `bsl-server/sync-platform-hbk.ps1`.
3. Сборка образа сервиса на VM:
   ```bash
   cd /home/kali/bsl-api        # Dockerfile, requirements.txt, app/
   docker build -t bsl-api:1.0.2 .
   ```
4. Стек в Portainer: **Stacks → Add stack → Web editor**, содержимое `docker-compose.yml`.
   В **Environment variables** добавить `BSL_SERVICE_TOKEN` (значение в `DEPLOY.local.md`), при необходимости `BSL_PORT`, `BSL_JIRA_BASE_URL`.
5. Или автоматически с VM: `deploy-portainer.py` (читает логин, пароль и токен из файлов chmod 600).
6. Проверка: `curl http://192.168.1.51:8080/health`.

Конфиг правил монтируется из `/home/kali/bsl-docker/config`, hbk — из `/home/kali/bsl-platform/bin` (read-only).

Миграция базы выполняется при старте: добавляются колонки `user` и `ticket`, существующие данные сохраняются.

## Обновление платформы (hbk)

```powershell
cd "E:\project\docker 1c\bsl-server"
.\sync-platform-hbk.ps1                       # 8.3.27.2342 по умолчанию
.\sync-platform-hbk.ps1 -Version 8.3.27.2214  # другая версия
```

Скрипт копирует `*.hbk` на VM и перезапускает `bsl-api`.

## Производительность

Одна проверка сейчас занимает **~18–22 с**: BSL LS заново разбирает 80 hbk при каждом запуске JVM. Замер LSP-режима (тёплый движок) показал 0,05 с на проверку, но пока результаты отличаются от batch-режима — см. `tests/lsp_bench.py` и обсуждение в плане.

## Тесты

Скрипты в `tests/`, токен не хранится в них — передаётся аргументом или файлом `.token`:

- `smoke.sh <токен> [порт]` — полный смоук-тест: токен, обязательный `user`, границы длин, файл, фильтры, журнал, UI.
- `check-deployed.sh [порт]` — то же для развёрнутого сервиса, токен из `.token`.
- `verify-rules.sh` — проверка диагностик через сервис.
- `run-smoke.sh` — поднять тестовый контейнер со случайным токеном и прогнать смоук (только на VM, для разработки).
- `run-smoke-remote.sh` — смоук-тест развёрнутого сервиса, токен из `.token`.
- `storage-audit.sh` — проверка, что текст кода не попадает в журнал, логи и каталоги данных.
- `timing.sh`, `cache-test.sh` — замеры времени.
- `lsp_bench.py` — замер тёплого LSP-движка.

## Файлы

| Файл | Назначение |
|---|---|
| `app/main.py` | FastAPI: эндпоинты, токен, валидация `user`/`ticket`, запуск BSL LS |
| `app/normalize.py` | приведение отчёта BSL к формату API |
| `app/journal.py` | журнал SQLite, миграция, статистика, разбивки |
| `app/ui.html` | веб-страница журнала и аналитики |
| `Dockerfile` | образ поверх `bsl-language-server:latest` (+python, uvicorn) |
| `docker-compose.yml` | стек для Portainer (тег `bsl-api:1.0.2`) |
| `deploy-portainer.py` | создание и обновление стека через API Portainer |
| `WEB-PAGES.md` | все адреса сервиса и страницы |
| `requirements.txt` | fastapi, uvicorn, python-multipart |
