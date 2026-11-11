# BSL check lega (bsl-check)

MCP-сервер (stdio) для OpenCode: тонкий HTTP-клиент к центральному сервису проверки BSL
(`bsl-api`, см. `../bsl-api/README.md`). SSH и копирование файлов не используются.

Имя сервера в MCP-протоколе — `BSL check lega`. Ключ в конфиге OpenCode — `bsl-check`
(поэтому инструмент вызывается как `bsl-check_check_bsl`).

```
OpenCode ──stdio──▶ BSL check lega (Node) ──HTTP──▶ bsl-api (VM, Portainer) ──▶ BSL LS
```

## Инструмент

`check_bsl` — проверить модуль 1С:

| Аргумент | Обязательность | Описание |
|---|---|---|
| `files` | один из `files` / `text` | массив абсолютных путей к `.bsl`/`.os`; каждый уходит в `POST /check/file` |
| `text`, `filename` | один из `files` / `text` | текст модуля и имя (уходит в `POST /check`) |
| `ticket` | нет | номер задачи Jira, например `ERP-1234`; до 50 символов |

Имя пользователя (`user`) сервис получает **автоматически**: из переменной `BSL_USER`, иначе из `USERNAME` Windows, иначе из учётной записи ОС. Если имя не определено, отправляется `неизвестно`. Аргумента для имени в инструменте нет — оно всегда берётся с машины, где запущен OpenCode.

Возвращает JSON: `ok` (все запросы прошли), `valid` (нет ошибок уровня Error во всех модулях), `results[]` — по каждому входу: `valid`, `summary`, `errors[]`, `warnings[]`, `text`, `user`, `ticket`, `duration_ms` (или `error`, если запрос не прошёл).

## Настройка (переменные окружения)

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `BSL_SERVICE_TOKEN` | — (обязательна) | общий токен команды (значение в `DEPLOY.local.md`) |
| `BSL_SERVICE_URL` | `http://192.168.1.51:8080` | адрес сервиса |
| `BSL_USER` | — | имя пользователя вручную (если не нужно имя из Windows) |
| `BSL_CLIENT_TIMEOUT_MS` | `180000` | таймаут одного запроса |

Токен задаётся **переменной окружения пользователя Windows** (не лежит в `opencode.json`):

```powershell
[Environment]::SetEnvironmentVariable('BSL_SERVICE_TOKEN', '<токен>', 'User')
```

После установки переменной перезапустите OpenCode, чтобы он её подхватил.

## Подключение в OpenCode

`C:\Users\lega\.config\opencode\opencode.jsonc` (глобально):

```json
"bsl-check": {
  "type": "local",
  "command": ["node", "E:\\project\\docker 1c\\bsl-mcp\\server.mjs"],
  "enabled": true
}
```

Инструмент в OpenCode: `bsl-check_check_bsl`.

## Проверка вручную

```powershell
cd "E:\project\docker 1c\bsl-mcp"
npm install        # один раз
npm start          # логи в stderr: [bsl-check-mcp] started; service=..., token=set, user=...
```

Для тестовых запусков с PowerShell не передавайте кириллицу через конвейер (`Get-Content | node`): PowerShell портит кодировку. Используйте перенаправление `node server.mjs < файл.jsonl` через `cmd /c`, файл пишите в UTF-8 без BOM.

## Требования

- Node.js ≥ 18 (проверено на 24).
- Доступ к `BSL_SERVICE_URL` из локальной сети.
