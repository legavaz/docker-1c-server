# BSL Language Server в Docker (проверка скриптов)

Статический анализ исходников 1С на языке BSL через **BSL Language Server**,
запускаемый в Docker на VM `kali` (`192.168.1.51`).

**Назначение:** отправить серверу скрипты (`.bsl`) — получить отчёт о замечаниях.
Интерактивный MCP-режим локального BSL **отключён** (`enabled: false` в
`E:\project\0509 git converter\opencode.json`), используется только batch-проверка.

> Версия jar: **1.0.7** (ваш `C:\tools\bsl\bsl-language-server.jar`).
> Java в образе: Eclipse Temurin **21** (поддерживаются 17/21/23).

---

## 1. Архитектура

```
Windows 192.168.1.57                     VM VirtualBox kali 192.168.1.51
┌──────────────────────────────┐         ┌─────────────────────────────────────────┐
│ E:\rep  (исходники 1С, .bsl) │  SMB    │ /srv/rep   (CIFS-монтирование шары)     │
│  шара \\192.168.1.57\rep     │────────▶│            │ (ro/rw)                     │
│  пользователь smb1c          │  445    │            ▼                            │
├──────────────────────────────┤  SMB    │ Docker: bsl-language-server             │
│ OpenCode Desktop             │────────▶│   -v /srv/rep:/work                     │
│  (MCP bsl — отключён)        │  445    │   -v /srv/bsl-reports:/reports          │
│                              │         │   analyze -s /work/<ПОДПАПКА> -o /reports│
└──────────────────────────────┘         └─────────────────────────────────────────┘
```

## 2a. Быстрая проверка присланных скриптов

`bsl-check.sh` — «проверить любой каталог со скриптами и получить отчёт»:

```bash
cd /home/kali/bsl-docker
./bsl-check.sh <каталог_с_bsl> [reporter...]

# примеры
./bsl-check.sh /srv/rep/task_git_file210 json console
./bsl-check.sh /home/kali/bsl-work/rep/_bsl_selftest json

# сводка по отчёту
python3 report-summary.py /srv/bsl-reports/bsl-json.json
```

- каталог монтируется в контейнер как `/work:ro` (только чтение — исходники не меняются);
- отчёты кладутся в `/srv/bsl-reports/` (`bsl-json.json` и др.);
- репортеры: `json`, `console`, `junit`, `tslint`, `generic`.

## 2. Состав проекта

| Путь | Назначение |
|---|---|
| `bsl-server/Dockerfile` | Образ: Temurin 21 JRE + jar, user `bsl`, `-Xmx4g` |
| `bsl-server/bsl.sh` | Обёртка запуска на VM (`analyze`/`format`/`version`/`raw`) |
| `bsl-server/bsl-check.sh` | Проверить произвольный каталог со скриптами и получить отчёт |
| `bsl-server/config/.bsl-language-server.json` | Конфиг BSL для batch |
| `bsl-server/vm-mount-rep.sh` | Монтирование SMB-шары `E:\rep` в `/srv/rep` (одноразово, sudo) |
| `bsl-server/report-summary.py` | Сводка по JSON-отчёту (файлы, замечания, топ-коды) |
| `bsl-server/selftest/Модуль.bsl` | Пробный модуль для самопроверки |

На VM рабочий каталог: **`/home/kali/bsl-docker/`**.

## 3. Сборка образа (на VM)

```bash
cd /home/kali/bsl-docker          # Dockerfile, bsl.sh, config/, dist/bsl-language-server.jar
docker build -t bsl-language-server:latest .

docker run --rm bsl-language-server:latest version   # => version: 1.0.7
```

Jar копируется на VM так:

```bash
# с Windows (Git bash):
scp -i /c/Users/lega/.ssh/opencode_vm \
  "/c/tools/bsl/bsl-language-server.jar" \
  kali@kali:/home/kali/bsl-docker/dist/
```

## 4. Доступ к исходникам (SMB-шара `E:\rep`)

### Windows (один раз, админ-PowerShell)
```powershell
$secure = ConvertTo-SecureString 'V8xKp3mQ7rTz9wLd' -AsPlainText -Force
New-LocalUser -Name smb1c -Password $secure -PasswordNeverExpires -AccountNeverExpires `
  -Description 'SMB read/write for 1C docker'
New-SmbShare -Name rep -Path 'E:\rep' -ChangeAccess smb1c
icacls 'E:\rep' /grant 'smb1c:(OI)(CI)M'
```

### VM (один раз, sudo)
```bash
sudo bash /home/kali/1c-docker/vm-mount-rep.sh   # из плана ранее: см. bsl-server/vm-mount-rep.sh
# монтирует //192.168.1.57/rep -> /srv/rep и добавляет запись в /etc/fstab
```
Учётные данные хранятся в `/etc/cifs-rep` (chmod 600).

> Пароль `smb1c` задан в скрипте и в чате — **смените** его после настройки.

## 5. Запуск анализа

Всё — на VM, через обёртку:

```bash
cd /home/kali/bsl-docker

# анализ подкаталога исходников (пути относительно /srv/rep), read-only
./bsl.sh analyze erp25_git/src/Catalogs json console

# версия сервера
./bsl.sh version

# произвольные аргументы jar
./bsl.sh raw analyze -s /work/<...> -r junit -o /reports
```

Переменные окружения (значения по умолчанию):

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `IMAGE` | `bsl-language-server:latest` | тег образа |
| `SRC_ROOT` | `/srv/rep` | хост-каталог исходников (монтируется в `/work`) |
| `REPORT_DIR` | `/srv/bsl-reports` | каталог отчётов (в `/reports`) |
| `CONFIG` | `<script>/config/.bsl-language-server.json` | конфиг BSL |

Репортеры (`-r`): `json`, `console`, `junit`, `tslint`, `generic` — можно несколько.
Отчёты пишутся в `/srv/bsl-reports` на VM.

### Контейнер запускается от текущего uid/gid
В `bsl.sh` используется `--user "$(id -u):$(id -g)"`, чтобы отчёты в примонтированном
каталоге создавались с правами пользователя VM (иначе — `Permission denied`).

### Кэш
Том `bsl-cache` (`/home/bsl/.bsl-language-server`) ускоряет повторные прогоны.

## 6. Сводка по отчёту

```bash
python3 /home/kali/bsl-docker/report-summary.py /srv/bsl-reports/bsl-json.json
```
Выводит: число файлов, общее число замечаний, распределение по severity, топ кодов.

## 7. Проверенный прогон (as-built)

| Параметр | Значение |
|---|---|
| Образ | `bsl-language-server:latest` (448 МБ) |
| Версия сервера | 1.0.7 |
| Каталог | `erp25_git/src/Catalogs` (5637 файлов `.bsl`) |
| Время | ~4–7 мин |
| Замечаний | **148 336** (Error 21 074, Warning 33 149, Information 24 805, Hint 69 308) |
| Отчёт | `/srv/bsl-reports/bsl-json.json` (~119 МБ) |
| Топ коды | `MissingSpace` 41 998, `LineLength` 19 103, `Typo` 16 044, `UnusedLocalVariable` 11 705, `MagicNumber` 5 979 |

## 8. `format` (изменяет файлы!)

```bash
./bsl.sh format erp25_git/src/Catalogs
```
Файлы правятся **по месту** в `/srv/rep` (то есть в `E:\rep` через шару). Перед первым
запуском сделайте бэкап/коммит. По умолчанию применяйте только к уже отформатированным
веткам.

## 9. Диагностика

| Симптом | Причина / решение |
|---|---|
| `Permission denied /reports/...json` | запуск не под нужным uid — в `bsl.sh` уже `--user $(id -u):$(id -g)`; либо `chmod` на `REPORT_DIR` |
| `No 1C platform installations found` | WARN: в контейнере нет платформы 1С (hbk). Диагностики работают; для type-aware — см. п. ниже |
| `Analyzing files... 0/0` | в каталоге нет `.bsl` (например, это файловая база `.1CD`, а не XML-выгрузка) |
| `useradd: UID 1000 is not unique` | в базовом образе uid занят — в Dockerfile нет `-u 1000` |
| Отчёт не появился в `/srv/bsl-reports` | проверьте `REPORT_DIR` (в оболочке) и права; по умолчанию пишет именно туда |

### type-aware анализ (опционально)
Для полной проверки типов можно положить в образ **hbk**-файлы платформы
(`C:\tools\bsl` или из пакетов 1С) и указать конфиг `v8platform`/`fromHbk`. Пока
используется анализ без платформенного контекста (части type-aware диагностики ограничены).

## 10. Обновление jar/версии

1. Заменить `dist/bsl-language-server.jar` (или скачать релиз).
2. Пересобрать: `docker build -t bsl-language-server:latest .`
3. Проверить: `./bsl.sh version`.

## 11. Локальный MCP

Отключён: в `E:\project\0509 git converter\opencode.json` у сервера
`bsl-language-server` стоит `"enabled": false`. Для задачи «проверить скрипты»
интерактивный режим не нужен — используется `bsl-check.sh`/`bsl.sh` в Docker.
Чтобы вернуть MCP, поставьте `"enabled": true` (или удалите атрибут) и перезапустите OpenCode.
