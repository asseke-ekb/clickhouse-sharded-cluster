# Подключение к ClickHouse кластеру через DBeaver

## Информация о кластере

У вас запущен кластер из 3 шардов ClickHouse на localhost.

### Порты доступа:

| Shard | HTTP Port | TCP Port (Native) | Hostname |
|-------|-----------|-------------------|----------|
| **Shard-1** (основной) | **8123** | **9000** | localhost |
| Shard-2 | 8124 | 9001 | localhost |
| Shard-3 | 8125 | 9002 | localhost |

---

## Установка драйвера ClickHouse в DBeaver

### Вариант 1: Автоматическая установка (рекомендуется)

1. Откройте **DBeaver**
2. Меню: `Database` → `Driver Manager`
3. Нажмите `New` (или найдите `ClickHouse` в списке)
4. Введите:
   - **Driver Name:** ClickHouse
   - **Class Name:** `com.clickhouse.jdbc.ClickHouseDriver`
   - **URL Template:** `jdbc:clickhouse://{host}:{port}/{database}`
   - **Default Port:** 8123
   - **Default Database:** default
5. Вкладка **Libraries** → `Download/Update` → DBeaver загрузит драйвер автоматически
6. Нажмите `OK`

### Вариант 2: Ручная установка

Если автоматическая установка не работает:

1. Скачайте драйвер: https://github.com/ClickHouse/clickhouse-java/releases
2. Выберите последнюю версию (например: `clickhouse-jdbc-x.x.x-shaded.jar`)
3. В DBeaver: `Database` → `Driver Manager` → `New`
4. Добавьте скачанный JAR файл в `Libraries`

---

## Создание подключения к Shard-1 (основной)

### Шаг 1: Создать новое подключение

1. Нажмите `Database` → `New Database Connection`
2. Выберите **ClickHouse** из списка драйверов
3. Нажмите `Next`

### Шаг 2: Настройка подключения

**Main табы:**

### Вариант 1: DBeaver пользователь (рекомендуется)

| Параметр | Значение |
|----------|----------|
| **Host** | `localhost` |
| **Port** | `8123` (HTTP) |
| **Database** | `default` |
| **Username** | `dbeaver` |
| **Password** | `dbeaver123` |

### Вариант 2: Admin пользователь

| Параметр | Значение |
|----------|----------|
| **Host** | `localhost` |
| **Port** | `8123` |
| **Database** | `default` |
| **Username** | `admin` |
| **Password** | `admin123` |

### Вариант 3: Default пользователь (без пароля, только localhost)

| Параметр | Значение |
|----------|----------|
| **Host** | `localhost` |
| **Port** | `8123` |
| **Database** | `default` |
| **Username** | `default` |
| **Password** | _(оставить пустым)_ |

### Шаг 3: Настройки драйвера (Driver properties)

Перейдите на вкладку **Driver properties** и добавьте (если нужно):

```
ssl=false
socket_timeout=300000
connection_timeout=10000
```

### Шаг 4: Проверка подключения

1. Нажмите `Test Connection...`
2. Если все настроено правильно, увидите: `Connected (ping: X ms)`
3. Нажмите `Finish`

---

## Альтернативный способ: через Native протокол (порт 9000)

ClickHouse поддерживает два протокола:
- **HTTP** (порт 8123) - рекомендуется для DBeaver
- **Native TCP** (порт 9000) - быстрее, но может требовать другой драйвер

### Подключение через HTTP (рекомендуется)

**JDBC URL:**
```
jdbc:clickhouse://localhost:8123/default
```

**Полная строка подключения:**
```
jdbc:clickhouse://localhost:8123/default?user=dbeaver&password=dbeaver123
```

### Подключение через Native TCP (опционально)

**JDBC URL:**
```
jdbc:ch://localhost:9000/default
```

---

## Проверка кластера в DBeaver

После успешного подключения выполните следующие запросы:

### 1. Проверить версию ClickHouse

```sql
SELECT version();
```

**Ожидаемый результат:** `24.8.14.39`

### 2. Проверить информацию о кластере

```sql
SELECT
    cluster,
    shard_num,
    host_name,
    port,
    is_local
FROM system.clusters
WHERE cluster = 'dwh_sharded_cluster'
ORDER BY shard_num;
```

**Ожидаемый результат:**
```
┌─cluster─────────────┬─shard_num─┬─host_name───────────┬─port─┬─is_local─┐
│ dwh_sharded_cluster │         1 │ clickhouse-shard-01 │ 9000 │        1 │
│ dwh_sharded_cluster │         2 │ clickhouse-shard-02 │ 9000 │        0 │
│ dwh_sharded_cluster │         3 │ clickhouse-shard-03 │ 9000 │        0 │
└─────────────────────┴───────────┴─────────────────────┴──────┴──────────┘
```

### 3. Проверить ZooKeeper подключение

```sql
SELECT * FROM system.zookeeper WHERE path = '/clickhouse';
```

**Ожидаемый результат:**
```
┌─name───────┬─value─┬─path────────┐
│ sessions   │       │ /clickhouse │
│ task_queue │       │ /clickhouse │
└────────────┴───────┴─────────────┘
```

### 4. Список баз данных

```sql
SHOW DATABASES;
```

### 5. Создать тестовую базу и таблицу (ON CLUSTER)

```sql
-- Создать БД на всех шардах
CREATE DATABASE IF NOT EXISTS test_dbeaver ON CLUSTER 'dwh_sharded_cluster';

-- Создать локальную таблицу на всех шардах
CREATE TABLE IF NOT EXISTS test_dbeaver.users ON CLUSTER 'dwh_sharded_cluster' (
    id UInt64,
    name String,
    email String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY id;

-- Создать Distributed таблицу (только на текущем шарде)
CREATE TABLE IF NOT EXISTS test_dbeaver.users_distributed AS test_dbeaver.users
ENGINE = Distributed('dwh_sharded_cluster', 'test_dbeaver', 'users', sipHash64(id));

-- Проверить таблицы
SHOW TABLES FROM test_dbeaver;
```

---

## Подключение ко всем 3 шардам отдельно

Вы можете создать 3 отдельных подключения в DBeaver для каждого шарда:

### Shard-1 Connection

```
Name: ClickHouse Shard-1 (Master)
Host: localhost
Port: 8123
Database: default
User: dbeaver
Password: dbeaver123
```

### Shard-2 Connection

```
Name: ClickHouse Shard-2
Host: localhost
Port: 8124
Database: default
User: dbeaver
Password: dbeaver123
```

### Shard-3 Connection

```
Name: ClickHouse Shard-3
Host: localhost
Port: 8125
Database: default
User: dbeaver
Password: dbeaver123
```

---

## Настройка Connection Settings (опционально)

В DBeaver можете настроить дополнительные параметры:

### Connection → Connection settings

- **Auto-commit:** ✅ Включить
- **Read-only:** ❌ Отключить (для записи данных)
- **Isolation level:** Default

### Connection → Initialization

Можно добавить SQL скрипт для выполнения при подключении:

```sql
-- Установить формат вывода
SET output_format_pretty_max_rows = 10000;
SET max_execution_time = 300;
```

---

## Troubleshooting

### Проблема: "No suitable driver found"

**Решение:**
1. Убедитесь, что драйвер ClickHouse установлен в DBeaver
2. `Database` → `Driver Manager` → найдите ClickHouse
3. Проверьте, что JAR файл добавлен в `Libraries`
4. Нажмите `Download/Update` для автоматической загрузки

### Проблема: "Connection refused"

**Решение:**
1. Проверьте, что контейнеры запущены:
   ```bash
   docker ps | grep clickhouse
   ```
2. Проверьте доступность порта:
   ```bash
   curl http://localhost:8123/
   ```
3. Убедитесь, что нет конфликтов портов

### Проблема: "Authentication failed"

**Решение:**
1. Попробуйте пользователя `default` без пароля
2. Или используйте `admin` с паролем `Astana2025!@Admin`
3. Проверьте файл `users.xml` в конфигурации

### Проблема: "Database does not exist"

**Решение:**
Создайте базу данных:
```sql
CREATE DATABASE IF NOT EXISTS mydb ON CLUSTER 'dwh_sharded_cluster';
```

---

## Полезные SQL запросы для работы в DBeaver

### Системная информация

```sql
-- Размер баз данных
SELECT
    database,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    count() as tables
FROM system.parts
WHERE active
GROUP BY database
ORDER BY sum(bytes) DESC;

-- Активные запросы
SELECT
    query_id,
    user,
    query,
    elapsed,
    formatReadableSize(memory_usage) as memory
FROM system.processes
ORDER BY elapsed DESC;

-- Медленные запросы (последние 24 часа)
SELECT
    type,
    query_duration_ms,
    query,
    formatReadableSize(read_bytes) as data_read,
    result_rows
FROM system.query_log
WHERE event_date >= today() - 1
  AND type = 'QueryFinish'
  AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC
LIMIT 20;
```

### Работа с Distributed таблицами

```sql
-- Проверить распределение данных по шардам
SELECT
    _shard_num,
    count() as row_count
FROM mydb.events_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

-- Запрос к конкретному шарду
SELECT * FROM mydb.events_local LIMIT 10;
```

---

## Рекомендации

1. **Используйте Shard-1** (порт 8123) как основное подключение
2. **Distributed таблицы** создавайте только на Shard-1
3. **ON CLUSTER команды** выполняйте с любого шарда - они автоматически применятся ко всем
4. **Для аналитики** подключайтесь к любому шарду - Distributed таблицы будут агрегировать данные со всех
5. **Для записи** используйте Distributed таблицы - данные автоматически распределятся по шардам

---

## Быстрая проверка подключения через curl

Перед настройкой DBeaver проверьте доступность:

```bash
# Shard-1
curl http://localhost:8123/
# Ответ: Ok.

# Shard-2
curl http://localhost:8124/
# Ответ: Ok.

# Shard-3
curl http://localhost:8125/
# Ответ: Ok.

# Выполнить SQL запрос
curl "http://localhost:8123/?query=SELECT+version()"
# Ответ: 24.8.14.39
```

---

**Готово!** Теперь вы можете подключиться к ClickHouse кластеру через DBeaver и работать с данными. 🚀

**Основное подключение:**
- Host: `localhost`
- Port: `8123`
- User: `dbeaver`
- Password: `dbeaver123`
