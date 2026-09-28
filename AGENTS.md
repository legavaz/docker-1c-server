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

Обёртка деплоя OpenCode: `Dockerfile` + `docker-compose.yml` + Helm-чарт.
Собранный на VM образ — `opencode-local`; контейнер `opencode`; UI http://192.168.1.51:4000.
