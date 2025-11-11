-- =========================================
-- ClickHouse Sharded Cluster Setup Examples
-- Cluster: dwh_sharded_cluster (3 shards, no replication)
-- =========================================

-- ==================== Step 1: Create Database ====================
-- ВАЖНО: Выполнить на КАЖДОМ шарде вручную!

-- На Shard-1:
CREATE DATABASE IF NOT EXISTS mydb;

-- На Shard-2:
CREATE DATABASE IF NOT EXISTS mydb;

-- На Shard-3:
CREATE DATABASE IF NOT EXISTS mydb;


-- ==================== Step 2: Create Local Tables ====================
-- ВАЖНО: Выполнить на КАЖДОМ шарде вручную!

-- На Shard-1, Shard-2, Shard-3:
CREATE TABLE mydb.events_local (
    id UUID,
    event_time DateTime,
    user_id UInt64,
    event_type LowCardinality(String),
    page_url String,
    session_id String,
    country LowCardinality(String),
    device_type LowCardinality(String),
    data String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time)
SETTINGS index_granularity = 8192;


-- ==================== Step 3: Create Distributed Table ====================
-- Выполнить ТОЛЬКО на одном шарде (например, Shard-1)
-- Эта таблица будет направлять запросы на все шарды

CREATE TABLE mydb.events_distributed AS mydb.events_local
ENGINE = Distributed(
    'dwh_sharded_cluster',    -- Имя кластера
    'mydb',                    -- Имя базы данных
    'events_local',            -- Локальная таблица
    sipHash64(user_id)         -- Функция шардирования (детерминированная)
);

-- Альтернативные варианты шардирования:
-- rand() - случайное распределение
-- sipHash64(id) - по UUID
-- user_id % 3 - простой модуль


-- ==================== Step 4: Insert Sample Data ====================
-- Вставка через Distributed таблицу (выполнить на Shard-1)

INSERT INTO mydb.events_distributed VALUES
    (generateUUIDv4(), now() - INTERVAL 1 HOUR, 12345, 'click', 'https://example.com/product/1', 'sess_001', 'KZ', 'desktop', '{"button": "buy"}', now()),
    (generateUUIDv4(), now() - INTERVAL 2 HOUR, 67890, 'view', 'https://example.com/home', 'sess_002', 'RU', 'mobile', '{}', now()),
    (generateUUIDv4(), now() - INTERVAL 3 HOUR, 11111, 'purchase', 'https://example.com/checkout', 'sess_003', 'US', 'tablet', '{"amount": 99.99}', now()),
    (generateUUIDv4(), now() - INTERVAL 4 HOUR, 22222, 'click', 'https://example.com/product/2', 'sess_004', 'KZ', 'desktop', '{"button": "add_to_cart"}', now()),
    (generateUUIDv4(), now() - INTERVAL 5 HOUR, 33333, 'view', 'https://example.com/catalog', 'sess_005', 'DE', 'mobile', '{}', now()),
    (generateUUIDv4(), now() - INTERVAL 6 HOUR, 44444, 'purchase', 'https://example.com/checkout', 'sess_006', 'FR', 'desktop', '{"amount": 149.99}', now());


-- ==================== Step 5: Query Examples ====================

-- Проверка распределения данных по шардам
SELECT
    _shard_num,
    count() as rows_count,
    uniq(user_id) as unique_users
FROM mydb.events_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

-- Агрегация по типу события
SELECT
    event_type,
    count() as cnt,
    uniq(user_id) as unique_users
FROM mydb.events_distributed
GROUP BY event_type
ORDER BY cnt DESC;

-- Топ стран по количеству событий
SELECT
    country,
    count() as events_count,
    countIf(event_type = 'purchase') as purchases_count
FROM mydb.events_distributed
GROUP BY country
ORDER BY events_count DESC
LIMIT 10;

-- Запрос с фильтрацией по user_id (оптимизированный)
-- ClickHouse отправит запрос только на нужный шард
SELECT *
FROM mydb.events_distributed
WHERE user_id = 12345
ORDER BY event_time DESC;

-- События за последний час
SELECT
    event_type,
    count() as cnt
FROM mydb.events_distributed
WHERE event_time >= now() - INTERVAL 1 HOUR
GROUP BY event_type;


-- ==================== Advanced Example: Materialized View ====================
-- ВАЖНО: Создать на КАЖДОМ шарде

-- На Shard-1, Shard-2, Shard-3:
CREATE TABLE mydb.events_by_hour_local (
    event_hour DateTime,
    event_type String,
    total_events UInt64,
    unique_users UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(event_hour)
ORDER BY (event_hour, event_type);

-- Материализованное представление (на каждом шарде)
CREATE MATERIALIZED VIEW mydb.events_by_hour_mv TO mydb.events_by_hour_local AS
SELECT
    toStartOfHour(event_time) as event_hour,
    event_type,
    count() as total_events,
    uniq(user_id) as unique_users
FROM mydb.events_local
GROUP BY event_hour, event_type;

-- Distributed таблица для агрегированных данных (только на Shard-1)
CREATE TABLE mydb.events_by_hour_distributed AS mydb.events_by_hour_local
ENGINE = Distributed('dwh_sharded_cluster', 'mydb', 'events_by_hour_local', rand());

-- Запрос к агрегированным данным
SELECT
    event_hour,
    event_type,
    sum(total_events) as total,
    sum(unique_users) as users
FROM mydb.events_by_hour_distributed
WHERE event_hour >= today() - INTERVAL 7 DAY
GROUP BY event_hour, event_type
ORDER BY event_hour DESC, total DESC;


-- ==================== User Management Examples ====================
-- Выполнить на КАЖДОМ шарде

-- Создание read-only пользователя
CREATE USER readonly_user IDENTIFIED BY 'SecurePassword123!';
GRANT SELECT ON mydb.* TO readonly_user;

-- Создание пользователя с правами записи
CREATE USER writer_user IDENTIFIED BY 'AnotherPassword456!';
GRANT SELECT, INSERT ON mydb.* TO writer_user;

-- Создание аналитика с ограничениями
CREATE USER analyst IDENTIFIED BY 'AnalystPass789!';
GRANT SELECT ON mydb.* TO analyst;
CREATE QUOTA analyst_quota FOR INTERVAL 1 hour MAX queries = 100, MAX execution_time = 3600 TO analyst;


-- ==================== Monitoring Queries ====================

-- Информация о кластере
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';

-- Размер таблиц по шардам
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE active AND database = 'mydb'
GROUP BY database, table;

-- Текущие запросы
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
    query,
    type,
    query_duration_ms,
    formatReadableSize(read_bytes) as read,
    result_rows
FROM system.query_log
WHERE event_date >= today() - 1
  AND type = 'QueryFinish'
  AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC
LIMIT 10;


-- ==================== Useful System Queries ====================

-- Проверка доступности всех шардов
SELECT
    shard_num,
    host_name,
    port,
    errors_count,
    estimated_recovery_time
FROM system.clusters
WHERE cluster = 'dwh_sharded_cluster';

-- Использование дисков
SELECT
    name,
    path,
    formatReadableSize(free_space) as free,
    formatReadableSize(total_space) as total,
    toString(round(free_space / total_space * 100, 2)) || '%' as free_percentage
FROM system.disks;

-- Активные части таблиц (для оптимизации)
SELECT
    database,
    table,
    count() as parts_count,
    sum(rows) as total_rows,
    formatReadableSize(sum(bytes_on_disk)) as size_on_disk
FROM system.parts
WHERE active
GROUP BY database, table
ORDER BY parts_count DESC;


-- ==================== Data Cleanup Examples ====================

-- Удаление старых партиций (выполнить на каждом шарде)
ALTER TABLE mydb.events_local DROP PARTITION '202401';

-- Оптимизация таблиц (объединение мелких частей)
OPTIMIZE TABLE mydb.events_local FINAL;

-- Удаление данных по условию
ALTER TABLE mydb.events_local DELETE WHERE event_time < now() - INTERVAL 90 DAY;


-- ==================== Performance Optimization ====================

-- Добавление индексов для быстрой фильтрации
ALTER TABLE mydb.events_local
ADD INDEX idx_session_id session_id TYPE bloom_filter GRANULARITY 1;

ALTER TABLE mydb.events_local
ADD INDEX idx_country country TYPE set(100) GRANULARITY 1;

-- Материализация индексов (требует пересборки таблицы)
ALTER TABLE mydb.events_local MATERIALIZE INDEX idx_session_id;
ALTER TABLE mydb.events_local MATERIALIZE INDEX idx_country;


-- ==================== Notes ====================
-- 1. Без ZooKeeper нельзя использовать ON CLUSTER для DDL
-- 2. Все DDL команды нужно выполнять вручную на каждом шарде
-- 3. Distributed таблицы создаются только на одном шарде (обычно на том, который используется для запросов)
-- 4. Локальные таблицы (MergeTree) должны быть идентичны на всех шардах
-- 5. Используйте детерминированную функцию шардирования (sipHash64) для равномерного распределения
-- 6. При отказе одного шарда теряется часть данных (нет репликации)
-- 7. Для production рекомендуется добавить репликацию с помощью ZooKeeper
