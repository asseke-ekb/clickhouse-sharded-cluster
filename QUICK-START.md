# ClickHouse Sharded Cluster - Быстрый старт

## Архитектура: 3 шарда + ZooKeeper = ОДИН СКРИПТ для всех!

```
┌──────────────────────────────────┐
│   ZooKeeper Quorum (3 nodes)    │  ← Координация
└──────────────────────────────────┘
              │
    ┌─────────┼─────────┐
    │         │         │
┌───▼───┐ ┌──▼───┐ ┌──▼───┐
│Shard-1│ │Shard-2│ │Shard-3│
│ (01)  │ │ (02)  │ │ (03)  │
└───────┘ └───────┘ └───────┘
```

## Что это дает?

✅ **Один SQL скрипт** выполняется сразу на всех 3 шардах
✅ **ON CLUSTER** команды - автоматическое создание таблиц
✅ **Distributed DDL** - синхронизация схемы через ZooKeeper
✅ **Горизонтальное масштабирование** данных между шардами

---

## Шаг 1: Запуск кластера (одной командой)

```bash
cd clickhouse_shard

# Создать директории для данных
mkdir -p data/zookeeper-{1,2,3} logs/zookeeper-{1,2,3}
mkdir -p shard-{1,2,3}/data/clickhouse shard-{1,2,3}/logs/clickhouse

# Запустить ВСЕ сервисы (3 ZooKeeper + 3 ClickHouse)
docker-compose -f docker-compose-full.yml up -d
```

**Что запустится:**
- `zookeeper-1`, `zookeeper-2`, `zookeeper-3` - координация кластера
- `clickhouse-shard-01`, `clickhouse-shard-02`, `clickhouse-shard-03` - ClickHouse узлы

---

## Шаг 2: Проверка статуса

```bash
# Проверить все контейнеры
docker ps

# Должны быть запущены 6 контейнеров:
# - 3 ZooKeeper (zookeeper-1, zookeeper-2, zookeeper-3)
# - 3 ClickHouse (clickhouse-shard-01, clickhouse-shard-02, clickhouse-shard-03)

# Проверить логи ClickHouse
docker logs clickhouse-shard-01 | grep "Ready for connections"

# Проверить ZooKeeper
docker exec zookeeper-1 sh -c "echo ruok | nc localhost 2181"
# Ответ: imok
```

---

## Шаг 3: Подключение к кластеру

```bash
# Подключиться к Shard-1 (главному для запросов)
docker exec -it clickhouse-shard-01 clickhouse-client

# Или через HTTP
curl http://localhost:8123/
```

**Доступные порты:**

| Shard | HTTP | TCP | Metrics |
|-------|------|-----|---------|
| Shard-1 | 8123 | 9000 | 9363 |
| Shard-2 | 8124 | 9001 | 9364 |
| Shard-3 | 8125 | 9002 | 9365 |

---

## Шаг 4: Создание таблиц (ОДИН СКРИПТ!)

Подключитесь к **любому** шарду и выполните:

```sql
-- 1. Создать базу данных на ВСЕХ шардах
CREATE DATABASE IF NOT EXISTS mydb ON CLUSTER 'dwh_sharded_cluster';

-- 2. Создать локальную таблицу на ВСЕХ шардах
CREATE TABLE IF NOT EXISTS mydb.events_local ON CLUSTER 'dwh_sharded_cluster' (
    id UUID,
    event_time DateTime,
    user_id UInt64,
    event_type String,
    data String
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time);

-- 3. Создать Distributed таблицу (на текущем шарде)
CREATE TABLE IF NOT EXISTS mydb.events_distributed AS mydb.events_local
ENGINE = Distributed('dwh_sharded_cluster', 'mydb', 'events_local', sipHash64(user_id));
```

**Результат:** Таблица `events_local` создана автоматически на всех 3 шардах!

---

## Шаг 5: Вставка данных

```sql
-- Вставить данные через Distributed таблицу
-- ClickHouse автоматически распределит их по шардам
INSERT INTO mydb.events_distributed VALUES
    (generateUUIDv4(), now(), 12345, 'click', 'button_1'),
    (generateUUIDv4(), now(), 67890, 'view', 'page_home'),
    (generateUUIDv4(), now(), 11111, 'purchase', 'product_42'),
    (generateUUIDv4(), now(), 22222, 'click', 'button_2'),
    (generateUUIDv4(), now(), 33333, 'view', 'catalog'),
    (generateUUIDv4(), now(), 44444, 'purchase', 'product_99');
```

---

## Шаг 6: Проверка распределения данных

```sql
-- Показать, сколько данных на каждом шарде
SELECT
    _shard_num as shard,
    count() as rows
FROM mydb.events_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

-- Результат:
-- ┌─shard─┬─rows─┐
-- │     1 │    2 │
-- │     2 │    2 │
-- │     3 │    2 │
-- └───────┴──────┘
```

---

## Шаг 7: Запросы к данным

```sql
-- Агрегация по всем шардам
SELECT
    event_type,
    count() as cnt
FROM mydb.events_distributed
GROUP BY event_type;

-- Запрос к конкретному пользователю (оптимизированный)
-- ClickHouse автоматически найдет нужный шард
SELECT *
FROM mydb.events_distributed
WHERE user_id = 12345;
```

---

## Управление кластером

### Просмотр информации о кластере

```sql
-- Информация о шардах
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';

-- Проверка ZooKeeper
SELECT * FROM system.zookeeper WHERE path = '/clickhouse';

-- Размер таблиц
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE active AND database = 'mydb'
GROUP BY database, table;
```

### Мониторинг Distributed DDL

```sql
-- Посмотреть историю DDL команд
SELECT
    host,
    port,
    status,
    query,
    exception
FROM system.distributed_ddl_queue
ORDER BY entry DESC
LIMIT 10;
```

---

## Удаление таблиц (одной командой)

```sql
-- Удалить Distributed таблицу (на текущем шарде)
DROP TABLE IF EXISTS mydb.events_distributed;

-- Удалить локальную таблицу на ВСЕХ шардах
DROP TABLE IF EXISTS mydb.events_local ON CLUSTER 'dwh_sharded_cluster';

-- Удалить базу данных на ВСЕХ шардах
DROP DATABASE IF EXISTS mydb ON CLUSTER 'dwh_sharded_cluster';
```

---

## Остановка кластера

```bash
cd clickhouse_shard

# Остановить все сервисы
docker-compose -f docker-compose-full.yml down

# Удалить ВСЕ данные (осторожно!)
docker-compose -f docker-compose-full.yml down -v
rm -rf data/ shard-*/data/ shard-*/logs/
```

---

## Важные команды

### Учетные данные

| User | Password | Access |
|------|----------|--------|
| admin | Astana2025!@Admin | Полный доступ |
| default | (пусто) | Localhost только |

### Подключение к шардам

```bash
# Shard-1
docker exec -it clickhouse-shard-01 clickhouse-client -u admin --password Astana2025!@Admin

# Shard-2
docker exec -it clickhouse-shard-02 clickhouse-client -u admin --password Astana2025!@Admin

# Shard-3
docker exec -it clickhouse-shard-03 clickhouse-client -u admin --password Astana2025!@Admin
```

### Выполнение SQL файла

```bash
# Выполнить setup-with-cluster.sql на Shard-1
docker exec -i clickhouse-shard-01 clickhouse-client -u admin --password Astana2025!@Admin < setup-with-cluster.sql
```

---

## Следующие шаги

1. **Изучите полные примеры:** [setup-with-cluster.sql](setup-with-cluster.sql)
2. **Читайте документацию:** [README.md](README.md)
3. **Настройте мониторинг:** Prometheus на портах 9363-9365
4. **Добавьте репликацию:** Для production окружения

---

## Отличия от версии без ZooKeeper

| Без ZooKeeper | С ZooKeeper |
|---------------|-------------|
| ❌ Нужно выполнять DDL на каждом шарде | ✅ Один скрипт для всех |
| ❌ CREATE TABLE ... (на каждом) | ✅ CREATE TABLE ... ON CLUSTER |
| ❌ Ручная синхронизация | ✅ Автоматическая координация |
| ❌ Нет Distributed DDL | ✅ Distributed DDL через ZooKeeper |

---

## Архитектура файлов

```
clickhouse_shard/
├── docker-compose-full.yml          ← ГЛАВНЫЙ ФАЙЛ для запуска
├── setup-with-cluster.sql           ← SQL примеры с ON CLUSTER
├── QUICK-START.md                   ← Этот файл
├── README.md                        ← Полная документация
├── shard-1/config/clickhouse/
│   ├── config.xml                   ← ZooKeeper настроен
│   └── users.xml
├── shard-2/config/clickhouse/
│   ├── config.xml                   ← ZooKeeper настроен
│   └── users.xml
└── shard-3/config/clickhouse/
    ├── config.xml                   ← ZooKeeper настроен
    └── users.xml
```

---

**Версия:** 2.0 (с ZooKeeper)
**Дата:** 2025-01-12
**Кластер:** dwh_sharded_cluster (3 shards + 3 ZooKeeper nodes)
