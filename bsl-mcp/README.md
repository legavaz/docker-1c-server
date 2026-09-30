# bsl-check-mcp

MCP-сервер (stdio), который принимает отредактированные файлы 1С (`.bsl`),
отправляет их на проверку в **BSL Language Server** (Docker на VM `kali`)
и возвращает **JSON-отчёт**.

```
OpenCode (Windows) ──stdio──▶ bsl-check-mcp (Node) ──ssh/scp──▶ VM kali
                                                                 │
                                                     docker run bsl-language-server
                                                                 │
                                                          /srv/bsl-reports/bsl-json.json
```

## Инструменты

| Tool | Аргументы | Что делает |
|---|---|---|
| `check_files` | `files: string[]`, `reporters?: string[]` | Проверить список файлов, вернуть JSON-отчёт |
| `check_dir` | `dir: string`, `reporters?: string[]` | Проверить каталог |
| `read_report` | — | Прочитать последний отчёт |

Возврат `check_files`/`check_dir`:

```json
{
  "ok": true,
  "reportPath": "/srv/bsl-reports/bsl-json.json",
  "targets": ["/srv/rep/..."],
  "results": [{ "exitCode": 0, "stderrTail": "" }],
  "errors": [],
  "report": { "fileinfos": [ ... ] }
}
```

`report` — это JSON-отчёт BSL как есть (`fileinfos[].diagnostics[]` с `code`,
`severity`, `message`, `range`).

## Как файлы попадают на VM

- Файлы внутри **SMB-шары** (`WSL_MAP`, по умолчанию `E:\rep` → `/srv/rep`)
  проверяются **на месте**, без копирования.
- Файлы **вне** шары копируются по `scp` в `VM_TMP_DIR` (inbox), проверяются и
  удаляются (если `KEEP_STAGED=false`).

## Настройка

`config.env` (рядом со `server.mjs`); переменные окружения перекрывают файл:

| Ключ | По умолчанию | Смысл |
|---|---|---|
| `SSH_HOST` | `kali` | SSH-хост VM (alias из `~/.ssh/config`) |
| `SSH_KEY` | `C:\Users\lega\.ssh\opencode_vm` | Приватный ключ |
| `SSH_BIN` / `SCP_BIN` | `C:\Program Files\Git\usr\bin\ssh.exe` / `scp.exe` | (в PATH Windows их нет) |
| `VM_BSL_DIR` | `/home/kali/bsl-docker` | Каталог с `bsl-check.sh` на VM |
| `VM_REPORT_DIR` | `/srv/bsl-reports` | Каталог отчётов на VM |
| `WSL_MAP` | `E:\rep=/srv/rep` | Карта Windows→VM (можно несколько через запятую) |
| `VM_TMP_DIR` | `/home/kali/bsl-inbox` | Куда копировать файлы вне шары |
| `TIMEOUT_MS` | `900000` | Таймаут одной операции |
| `KEEP_STAGED` | `false` | Оставлять ли копии файлов на VM |

## Подключение к OpenCode

В `opencode.json` (глобальном или проекта):

```json
{
  "mcp": {
    "bsl-check": {
      "type": "local",
      "command": ["node", "E:\\project\\docker 1c\\bsl-mcp\\server.mjs"],
      "enabled": true
    }
  }
}
```

После перезапуска OpenCode появятся инструменты `bsl-check_check_files`,
`bsl-check_check_dir`, `bsl-check_read_report`.

## Установка зависимостей

```powershell
cd "E:\project\docker 1c\bsl-mcp"
npm install
```

## Требования

- Node.js ≥ 18 (проверено на 24).
- Git for Windows (даёт `ssh.exe`/`scp.exe`).
- На VM: собранный образ `bsl-language-server` и `bsl-check.sh` в `VM_BSL_DIR`.
- SSH-доступ к VM по ключу (см. `AGENTS.md`).

## Ручной запуск (отладка)

```powershell
npm start
# или
node server.mjs
```
Логи идут в `stderr` (`[bsl-check-mcp] ...`).

## Пример вызова (в OpenCode)

> Проверь BSL эти файлы: E:\rep\...\Module.bsl

Агент вызовет `bsl-check_check_files` и получит JSON-отчёт.

## Известные тонкости

- В PATH Windows нет `ssh`/`scp` — используются пути Git for Windows (`SSH_BIN`/`SCP_BIN`).
- Команды на VM передаются в `stdin` (`ssh kali bash -s`), чтобы кавычки и
  UTF-8 (кириллица) в путях не искажались.
- Отчёт общий (`bsl-json.json`) перезаписывается каждым вызовом — при
  параллельных проверках возможна гонка. Для последовательного использования ок.
