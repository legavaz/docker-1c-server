# AGENTS.md

Инструкции для агента по этому репозиторию.

## Окружение (прочитать первым)

- **Docker НЕ локальный.** Docker Desktop на Windows не используется (остановлен/сломан).
- Docker работает **внутри VM VirtualBox**:
  - VM: host `kali` = `192.168.1.51`, `Kali GNU/Linux Rolling 2026.1` (VirtualBox guest, группа `vboxsf`).
  - Docker на VM: `docker.io` 28.5.2 (+ buildx, containerd), служба `docker` активна.
  - Пользователь `kali` входит в группу `docker`; `sudo` требует пароль (NOPASSWD не настроен).
- SSH-доступ: `ssh kali@kali`, ключ `C:\Users\lega\.ssh\opencode_vm`.
- Локальные детали и доступы: `DEPLOY.local.md` (в `.gitignore`, не коммитится).

## Как выполнять docker-команды

Docker-команды запускать **на VM через SSH**. Пример (через Git bash, чтобы PowerShell 5.1
не портил кавычки в аргументах нативных программ):

```powershell
& "C:\Program Files\Git\usr\bin\bash.exe" -lc "ssh -i /c/Users/lega/.ssh/opencode_vm kali@kali 'docker ps'"
```

Правила кавычек при вызове:
- внешняя PowerShell-строка — в **двойных** кавычках;
- удалённая команда — в **одинарных**; не встраивать внутрь двойные кавычки;
- избегать `|` внутри аргументов (`grep -e A -e B` вместо `grep "A|B"`).

## Что это за проект

Репозиторий `legavaz/docker-1c-server` (публичный) содержит несколько независимых частей:

| Путь | Что это | Статус |
|---|---|---|
| `1c-server/` | сервер 1С:Предприятие 8.3.27.2342 в Docker, подключение к PostgreSQL | действующий |
| `bsl-server/` | BSL Language Server в Docker: batch-проверка каталогов, образ, скрипт обновления hbk | действующий |
| `bsl-api/` | центральный HTTP-сервис проверки BSL: журнал, статистика, страница `/ui`, Swagger | действующий, стек `bsl` в Portainer |
| `bsl-mcp/` | MCP-сервер «BSL check lega» для OpenCode (HTTP-клиент к `bsl-api`) | действующий |
| корень: `Dockerfile`, `makefile`, `container/`, `arh/` | унаследованный образ 1С из исходного репозитория, не относится к текущим задачам | устаревший |

