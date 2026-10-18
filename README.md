# PostgreSQL + pgAdmin в Docker

Локальное окружение для работы с PostgreSQL 18 через веб-интерфейс pgAdmin 4. Подключение к серверу в pgAdmin настроено заранее, полезные расширения включаются при первом запуске.

## Состав

| Сервис     | Образ                   | Порт по умолчанию | Назначение                  |
|------------|-------------------------|-------------------|-----------------------------|
| `postgres` | `postgres:18`           | `5432`            | Сервер БД                   |
| `pgadmin`  | `dpage/pgadmin4:latest` | `5050`            | Веб-интерфейс администрирования |

```
.
├── compose.yaml            # описание сервисов
├── .env                    # логины, пароли, порты, часовой пояс
├── initdb/
│   └── 01-extensions.sql   # выполняется один раз при инициализации БД
└── pgadmin/
    └── servers.json        # преднастроенное подключение к серверу
```

## Требования

- Docker с плагином Compose v2 (`docker compose`)

## Быстрый старт

```bash
git clone <url-репозитория>
cd postgres-pgadmin
docker compose up -d
```

Проверить состояние:

```bash
docker compose ps
```

pgAdmin запускается только после того, как PostgreSQL пройдёт healthcheck.

## Доступ

**pgAdmin:** http://localhost:5050
- Логин: `admin@example.com`
- Пароль: `admin`

Сервер `Local PostgreSQL` уже есть в дереве слева, при первом подключении нужно ввести пароль пользователя `postgres`.

**PostgreSQL** (для внешних клиентов: DBeaver, psql, приложения):

| Параметр | Значение    |
|----------|-------------|
| Host     | `localhost` |
| Port     | `5432`      |
| User     | `postgres`  |
| Password | `postgres`  |
| Database | `appdb`     |

Внутри Docker-сети (например, из pgAdmin) хост — `postgres`.

Подключение через psql в контейнере:

```bash
docker exec -it postgres psql -U postgres -d appdb
```

## Настройка

Все параметры задаются в `.env`:

| Переменная          | По умолчанию        | Описание                    |
|---------------------|---------------------|-----------------------------|
| `POSTGRES_USER`     | `postgres`          | Суперпользователь БД        |
| `POSTGRES_PASSWORD` | `postgres`          | Пароль суперпользователя    |
| `POSTGRES_DB`       | `appdb`             | База, создаваемая при старте |
| `POSTGRES_PORT`     | `5432`              | Порт на хосте               |
| `PGADMIN_EMAIL`     | `admin@example.com` | Логин в pgAdmin             |
| `PGADMIN_PASSWORD`  | `admin`             | Пароль в pgAdmin            |
| `PGADMIN_PORT`      | `5050`              | Порт pgAdmin на хосте       |
| `TZ`                | `Asia/Vladivostok`  | Часовой пояс сервера        |

> Пароли учебные. Если окружение доступно не только с локальной машины, замените их и не публикуйте порт `5432` наружу.

## Расширения

При первой инициализации скрипт `initdb/01-extensions.sql` включает:

- `pg_trgm`: поиск по похожести строк, индексы для `LIKE '%...%'`
- `btree_gist`: скалярные типы в GiST-индексах, ограничения исключения
- `pg_stat_statements`: статистика выполнения запросов (загружается через `shared_preload_libraries` в `compose.yaml`)

### Как включить другие расширения на работающем сервере

**Расширения из образа** (`hstore`, `ltree`, `pgcrypto`, `uuid-ossp`, `pageinspect`, `postgres_fdw` и др.) включаются без перезапуска:

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
```

Список доступных расширений: `SELECT * FROM pg_available_extensions;`

**Расширения с предзагрузкой** (`auto_explain`, `pg_prewarm` и т.п.) нужно дописать в `command` в `compose.yaml`:

```yaml
command: ["postgres", "-c", "shared_preload_libraries=pg_stat_statements,auto_explain"]
```

затем выполнить `docker compose up -d`.

**Сторонние расширения** (PostGIS, pgvector и др.) требуют другого образа той же мажорной версии, например `postgis/postgis:18-3.6` или `pgvector/pgvector:pg18`.

### Параметры сервера

```sql
ALTER SYSTEM SET work_mem = '64MB';
SELECT pg_reload_conf();
```

Параметры вроде `shared_buffers` и `max_connections` применяются только после перезапуска: `docker compose restart postgres`.

## Управление

```bash
docker compose up -d            # запустить
docker compose stop             # остановить
docker compose restart postgres # перезапустить PostgreSQL
docker compose logs -f postgres # логи
docker compose down             # удалить контейнеры (данные сохранятся)
docker compose down -v          # удалить контейнеры и тома (ДАННЫЕ БУДУТ УДАЛЕНЫ)
```

## Данные и бэкапы

Данные хранятся в именованных томах `pgdata` и `pgadmin_data` и переживают пересоздание контейнеров.

Резервная копия и восстановление:

```bash
docker exec postgres pg_dump -U postgres -Fc appdb > appdb.dump
docker exec -i postgres pg_restore -U postgres -d appdb --clean < appdb.dump
```

## Важно

- Скрипты из `initdb/` и файл `pgadmin/servers.json` применяются **только при первом запуске**, пока тома пустые. Чтобы применить изменения в них, нужен `docker compose down -v` (с потерей данных) или ручное выполнение.
- Начиная с PostgreSQL 18 том монтируется в `/var/lib/postgresql`, а не в `/var/lib/postgresql/data`.
- Смена мажорной версии (например, 18 → 19) простой заменой образа не работает: нужен `pg_dump`/`pg_restore` или `pg_upgrade`.
