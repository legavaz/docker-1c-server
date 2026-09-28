# Сервер 1С:Предприятие 8.3 в Docker

Развёртывание серверной части **1С:Предприятие 8.3.27.2342** в Docker на базе
Ubuntu 22.04, с подключением информационных баз к **PostgreSQL**.

- Образ: `1c-server:8.3.27.2342`
- Контейнер: `1c-server`
- Docker-хост: VM `kali` (`192.168.1.51`)
- СУБД для ИБ: PostgreSQL `192.168.1.57:5432` (1C-сборка `18.4-1.1C`)

---

## 1. Архитектура

```
┌────────────────────────────┐        ┌──────────────────────────────┐
│ Windows-хост 192.168.1.57  │        │ VM VirtualBox kali           │
│                            │        │ 192.168.1.51 (Kali Rolling)  │
│  PostgreSQL 18.4-1.1C      │◀───────│                              │
│   (служба pgsql-18.4-1.1C) │  5432  │  Docker                      │
│   данные: E:\postgres      │        │   └── контейнер 1c-server    │
│                            │        │        (network_mode: host)  │
└────────────────────────────┘        │        ragent/rmngr/rph/ras  │
        ▲                             └──────────────────────────────┘
        │                                        ▲
   клиент 1С (Конфигуратор/тонкий) ────── 1540 ───┘  (агент кластера)
```

- Клиенты 1С подключаются к серверному агенту на `192.168.1.51:1540`.
- Кластер 1С обращается к PostgreSQL на `192.168.1.57:5432`.
- Контейнер использует **host-сеть**: кластер отдаёт клиентам адрес рабочего
  процесса (rphost), поэтому NAT-проброс портов из bridge-сети не работает.

## 2. Состав проекта

| Путь | Назначение |
|---|---|
| `1с install - deb/` | Пакеты 1С:Предприятие 8.3.27.2342 (`.deb`, amd64): server, server-nls, common, common-nls, crs, ws, ws-nls |
| `1c-server/Dockerfile` | Сборка образа: Ubuntu 22.04 + установка `.deb` из `dist/` |
| `1c-server/entrypoint.sh` | Точка входа: запуск `ras` + `ragent` |
| `1c-server/docker-compose.yml` | Описание сервиса (альтернатива `run.sh`) |
| `1c-server/run.sh` | Хелпер управления контейнером на VM |
| `1c-server/pg_setup.sql` | Ручная подготовка БД PostgreSQL (альтернатива `--create-database`) |
| `1c-server/pg_check.sql` | Диагностический запрос: версия PG, базы, роли |
| `1c-server/logcfg.xml` | Технологический журнал 1С для диагностики |
| `AGENTS.md` | Инструкции по окружению (SSH, запуск docker на VM) |

На VM рабочий каталог сборки: **`/home/kali/1c-docker/`** (там же `dist/` с `.deb`).

## 3. Требования

- Docker на VM `kali` (Docker 28.5.2, служба `docker` активна).
- Свободно ≥ 5 ГБ (образ ~2.6 ГБ + данные).
- PostgreSQL **1C-сборки** с расширениями `mchar`, `fasttrun`, `fulleq`
  (ванильный PostgreSQL не подойдёт — см. раздел 7).
- Сетевой доступ VM → PostgreSQL:5432 и клиентов → `192.168.1.51:1540`.

## 4. Сборка образа

На VM:

```bash
cd /home/kali/1c-docker          # Dockerfile + entrypoint.sh + dist/*.deb
docker build -t 1c-server:8.3.27.2342 .
```

`.deb`-пакеты копируются в Docker-контекст как `dist/`:

```bash
# с Windows (через Git bash):
scp -i /c/Users/lega/.ssh/opencode_vm "/e/project/docker 1c/1с install - deb/"*.deb \
    kali@kali:/home/kali/1c-docker/dist/
```

## 5. Запуск и управление

> На VM **нет плагина `docker compose`** (только `docker.io`). Поэтому запуск —
> через `run.sh` или `docker run`. Файл `docker-compose.yml` оставлен как описание.

```bash
cd /home/kali/1c-docker

./run.sh up       # создать и запустить контейнер
./run.sh ps       # статус
./run.sh logs     # логи (Ctrl+C для выхода)
./run.sh down     # остановить и удалить контейнер
./run.sh rac <аргументы rac>   # выполнить rac внутри контейнера
```

Эквивалент `up` вручную:

```bash
docker run -d --name 1c-server --restart unless-stopped --network host \
  -e ONEC_RANGE=1560:1591 \
  -v 1c-data:/home/usr1cv8/.1cv8 \
  -v 1c-logs:/var/log/1c \
  1c-server:8.3.27.2342
```

> ⚠️ **Не добавляйте `--hostname`** при `--network host`: `ragent` падает и
> контейнер уходит в бесконечный рестарт. (По этой же причине в
> `docker-compose.yml` нет поля `hostname`.)

## 6. Параметры контейнера

### Переменные окружения (`entrypoint.sh`)

| Переменная | По умолчанию | Описание |
|---|---|---|
| `ONEC_DATA_DIR` | `/home/usr1cv8/.1cv8/1C/1cv8` | Каталог данных кластера |
| `ONEC_LOG_DIR` | `/var/log/1c` | Каталог логов |
| `ONEC_AGENT_PORT` | `1540` | Порт серверного агента (`-port`) |
| `ONEC_REGPORT` | `1541` | Порт менеджера кластера (`-regport`) |
| `ONEC_RANGE` | `1560:1591` | Диапазон портов рабочих процессов (`-range`) |
| `ONEC_SECLEV` | `0` | Уровень безопасности (`-seclev`) |
| `ONEC_PING_PERIOD` | `1000` | `-pingPeriod`, мс |
| `ONEC_PING_TIMEOUT` | `5000` | `-pingTimeout`, мс |
| `ONEC_DEBUG` | *(пусто)* | Аргументы отладки, напр. `-debug` |
| `ONEC_START_RAS` | `1` | Запускать `ras` (сервер удалённого администрирования) |
| `ONEC_RAS_PORT` | `1545` | Порт `ras` |

### Порты

| Порт | Процесс | Назначение |
|---|---|---|
| `1540` | `ragent` | Подключение клиентов 1С (агент кластера) |
| `1541` | `rmngr` | Менеджер кластера |
| `1545` | `ras` | Администрирование через `rac` |
| `1560–1591` | `rphost` | Рабочие процессы |

### Тома

| Том | Точка монтирования | Содержимое |
|---|---|---|
| `1c-data` | `/home/usr1cv8/.1cv8` | Реестр кластера, данные сервера |
| `1c-logs` | `/var/log/1c` | Логи и техжурнал |

## 7. PostgreSQL: обязательное расширение `mchar`

При создании информационной базы 1С проверяет в БД наличие расширения
**`mchar`**. Если его нет — операция падает с ошибкой:

```
Ошибка СУБД:
DATABASE не пригоден для использования
```

Что важно:

- **Ванильный PostgreSQL не подходит.** В нём нет расширения `mchar`; 1С
  получит `ERROR: extension "mchar" is not available`. Нужна **1C-сборка**
  PostgreSQL, в которой есть `mchar` (а также `fasttrun`, `fulleq`).
- **Не создавайте БД для 1С вручную без расширений.** Пустая БД без `mchar`
  распознаётся 1С как «не пригодная».
- Разрешить подключение в `pg_hba.conf` на стороне PostgreSQL для IP сервера 1С.

### Настройка `pg_hba.conf` (пример для Windows-хоста)

В `E:\postgres\pg_hba.conf` добавлена строка для VM:

```
host    all             all             192.168.1.51/32         md5
```

Применить без перезапуска: `SELECT pg_reload_conf();`

## 8. Создание информационной базы

**Рекомендуемый способ** — дать 1С создать БД и установить расширения:

```bash
docker exec 1c-server /opt/1cv8/x86_64/8.3.27.2342/rac infobase create \
  --cluster=<CLUSTER_ID> \
  --name=<ИМЯ_ИБ> \
  --dbms=PostgreSQL \
  --db-server=<PG_HOST> \
  --db-name=<DB_NAME> \
  --db-user=<DB_USER> \
  --db-pwd=<DB_PASSWORD> \
  --create-database \
  --locale=ru_RU
```

Требуется пользователь PostgreSQL с правом `CREATEDB` (и правом `CREATE EXTENSION`,
т.е. суперпользователь).

**Альтернатива** — подготовить БД заранее (см. `pg_setup.sql`: создаёт роль, БД и
расширения `mchar`/`fasttrun`/`fulleq`), затем создать ИБ **без** `--create-database`.

Просмотр:

```bash
docker exec 1c-server /opt/1cv8/x86_64/8.3.27.2342/rac cluster list
docker exec 1c-server /opt/1cv8/x86_64/8.3.27.2342/rac infobase summary list --cluster=<CLUSTER_ID>
```

> Синтаксис `rac infobase list` неверен (выдаёт «Ошибка соединения с сервером …
> Already open»). Используйте `rac infobase summary list`.

## 9. Текущий стенд (as-built)

| Параметр | Значение |
|---|---|
| Кластер | имя `Локальный кластер`, id `3799e955-b46d-4b74-b1b4-7d12eaf8e53a` |
| Серверный агент | `192.168.1.51:1540` |
| `ras` | `192.168.1.51:1545` |
| Информационная база | имя `base1c`, uuid `ac7be956-bf4d-42d6-8774-4d9ae0d9d527` |
| СУБД ИБ | PostgreSQL `192.168.1.57:5432`, БД `base_main`, пользователь `postgres` |
| Расширения в БД | `mchar 2.2.1`, `fasttrun 2.0`, `fulleq 2.0` |

Подключение клиента: сервер `192.168.1.51`, порт `1540`, имя ИБ `base1c`.
База пустая (без конфигурации) — открывать в Конфигураторе 1С 8.3.27.

## 10. Диагностика

### Технологический журнал 1С

```bash
docker cp logcfg.xml 1c-server:/opt/1cv8/conf/logcfg.xml
docker cp logcfg.xml 1c-server:/home/usr1cv8/.1cv8/conf/logcfg.xml
docker cp logcfg.xml 1c-server:/home/usr1cv8/.1cv8/1C/1cv8/conf/logcfg.xml
docker restart 1c-server
# логи: /var/log/1c/tech/<process>_<pid>/<ггммддчч>.log
```

Событие `DBPOSTGRS` показывает SQL к PostgreSQL, `EXCP` — исключения.

### Проверка PostgreSQL

```bash
PGPASSWORD=<PG_PASSWORD> psql -h 192.168.1.57 -U postgres -f 1c-server/pg_check.sql
```

### Типовые проблемы

| Симптом | Причина / решение |
|---|---|
| `DATABASE не пригоден для использования` | В БД нет расширения `mchar`. Создавайте БД через `--create-database` |
| `extension "mchar" is not available` | PostgreSQL не 1C-сборки (в нём нет `mchar`) |
| `no pg_hba.conf entry for host "192.168.1.51"` | Добавить запись в `pg_hba.conf` и `pg_hba reload` |
| Контейнер циклически перезапускается | Убран `--hostname` при `--network host` |
| `row number 0 is out of range 0..-1` | Следствие проверки `mchar` (см. выше) |
| `rac infobase list` → `Already open` | Использовать `rac infobase summary list` |

## 11. Обновление версии платформы

1. Положить `.deb` новой версии в `1с install - deb/`.
2. Скопировать в `dist/` на VM и обновить `V8_VERSION` в `Dockerfile` и
   `entrypoint.sh` (путь `/opt/1cv8/x86_64/<версия>/`).
3. Пересобрать образ и пересоздать контейнер (`./run.sh up`).

## 12. Безопасность

- **Пароли БД не хранить в репозитории.** В примерах — плейсхолдеры
  `<PG_PASSWORD>`, `<DB_PASSWORD>`. Реальные доступы — в `DEPLOY.local.md`
  (в `.gitignore`, не коммитится).
- ИБ создаётся под суперпользователем `postgres` — для эксплуатации
  предпочтительнее завести отдельную роль-владельца БД.
- Ограничивать `pg_hba.conf` конкретными адресами (не `0.0.0.0/0`).
- Порт `1540` (агент) доступен в сети — при необходимости ограничить firewall.
