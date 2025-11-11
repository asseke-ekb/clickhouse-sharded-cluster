-- =========================================
-- ClickHouse Sharded Cluster Setup with ZooKeeper
-- ONE SCRIPT FOR ALL SHARDS using ON CLUSTER
-- Cluster: dwh_sharded_cluster (3 shards, with ZooKeeper coordination)
-- =========================================

-- ==================== Step 1: Create Database on ALL Shards ====================
-- Выполнить один раз на любом шарде, автоматически создастся на всех

CREATE DATABASE IF NOT EXISTS mydb ON CLUSTER 'dwh_sharded_cluster';


-- ==================== Step 2: Create Local Tables on ALL Shards ====================
-- Один запрос создаст таблицу на всех шардах автоматически!

CREATE TABLE IF NOT EXISTS mydb.events_local ON CLUSTER 'dwh_sharded_cluster' (
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
-- Создать на ОДНОМ шарде (например, Shard-1)
-- Эта таблица направляет запросы на все шарды

CREATE TABLE IF NOT EXISTS mydb.events_distributed AS mydb.events_local
ENGINE = Distributed(
    'dwh_sharded_cluster',    -- Имя кластера
    'mydb',                    -- Имя базы данных
    'events_local',            -- Локальная таблица
    sipHash64(user_id)         -- Функция шардирования (детерминированная)
);


-- ==================== Step 4: Insert Sample Data ====================
-- Вставка через Distributed таблицу (выполнить на любом шарде)

INSERT INTO mydb.events_distributed VALUES
    (generateUUIDv4(), now() - INTERVAL 1 HOUR, 12345, 'click', 'https://example.com/product/1', 'sess_001', 'KZ', 'desktop', '{"button": "buy"}', now()),
    (generateUUIDv4(), now() - INTERVAL 2 HOUR, 67890, 'view', 'https://example.com/home', 'sess_002', 'RU', 'mobile', '{}', now()),
    (generateUUIDv4(), now() - INTERVAL 3 HOUR, 11111, 'purchase', 'https://example.com/checkout', 'sess_003', 'US', 'tablet', '{"amount": 99.99}', now()),
    (generateUUIDv4(), now() - INTERVAL 4 HOUR, 22222, 'click', 'https://example.com/product/2', 'sess_004', 'KZ', 'desktop', '{"button": "add_to_cart"}', now()),
    (generateUUIDv4(), now() - INTERVAL 5 HOUR, 33333, 'view', 'https://example.com/catalog', 'sess_005', 'DE', 'mobile', '{}', now()),
    (generateUUIDv4(), now() - INTERVAL 6 HOUR, 44444, 'purchase', 'https://example.com/checkout', 'sess_006', 'FR', 'desktop', '{"amount": 149.99}', now()),
    (generateUUIDv4(), now() - INTERVAL 7 HOUR, 55555, 'view', 'https://example.com/about', 'sess_007', 'KZ', 'mobile', '{}', now()),
    (generateUUIDv4(), now() - INTERVAL 8 HOUR, 66666, 'click', 'https://example.com/contact', 'sess_008', 'GB', 'desktop', '{}', now()),
    (generateUUIDv4(), now() - INTERVAL 9 HOUR, 77777, 'purchase', 'https://example.com/checkout', 'sess_009', 'US', 'desktop', '{"amount": 299.99}', now()),
    (generateUUIDv4(), now() - INTERVAL 10 HOUR, 88888, 'view', 'https://example.com/catalog/electronics', 'sess_010', 'RU', 'tablet', '{}', now());


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
    countIf(event_type = 'purchase') as purchases_count,
    sum(toFloat64OrZero(JSONExtractString(data, 'amount'))) as total_amount
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


-- ==================== Advanced Example: Aggregated Tables ====================
-- Создание агрегированной таблицы на всех шардах одной командой!

CREATE TABLE IF NOT EXISTS mydb.events_by_hour_local ON CLUSTER 'dwh_sharded_cluster' (
    event_hour DateTime,
    event_type String,
    country String,
    total_events UInt64,
    unique_users UInt64
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(event_hour)
ORDER BY (event_hour, event_type, country);

-- Материализованное представление (на всех шардах)
CREATE MATERIALIZED VIEW IF NOT EXISTS mydb.events_by_hour_mv ON CLUSTER 'dwh_sharded_cluster'
TO mydb.events_by_hour_local AS
SELECT
    toStartOfHour(event_time) as event_hour,
    event_type,
    country,
    count() as total_events,
    uniq(user_id) as unique_users
FROM mydb.events_local
GROUP BY event_hour, event_type, country;

-- Distributed таблица для агрегированных данных (на одном шарде)
CREATE TABLE IF NOT EXISTS mydb.events_by_hour_distributed AS mydb.events_by_hour_local
ENGINE = Distributed('dwh_sharded_cluster', 'mydb', 'events_by_hour_local', rand());

-- Запрос к агрегированным данным
SELECT
    event_hour,
    event_type,
    country,
    sum(total_events) as total,
    sum(unique_users) as users
FROM mydb.events_by_hour_distributed
WHERE event_hour >= today() - INTERVAL 7 DAY
GROUP BY event_hour, event_type, country
ORDER BY event_hour DESC, total DESC
LIMIT 100;


-- ==================== User Management ====================
-- Создание пользователей на всех шардах одной командой

-- Read-only пользователь
CREATE USER IF NOT EXISTS readonly_user ON CLUSTER 'dwh_sharded_cluster'
    IDENTIFIED BY 'SecurePassword123!';

GRANT SELECT ON mydb.* TO readonly_user ON CLUSTER 'dwh_sharded_cluster';

-- Пользователь с правами записи
CREATE USER IF NOT EXISTS writer_user ON CLUSTER 'dwh_sharded_cluster'
    IDENTIFIED BY 'WriterPassword456!';

GRANT SELECT, INSERT ON mydb.* TO writer_user ON CLUSTER 'dwh_sharded_cluster';

-- Аналитик с ограничениями
CREATE USER IF NOT EXISTS analyst ON CLUSTER 'dwh_sharded_cluster'
    IDENTIFIED BY 'AnalystPass789!';

GRANT SELECT ON mydb.* TO analyst ON CLUSTER 'dwh_sharded_cluster';

-- Создание квоты для аналитика
CREATE QUOTA IF NOT EXISTS analyst_quota ON CLUSTER 'dwh_sharded_cluster'
    FOR INTERVAL 1 hour MAX queries = 100, MAX execution_time = 3600;

-- Применить квоту
ALTER USER analyst ON CLUSTER 'dwh_sharded_cluster' QUOTA analyst_quota;


-- ==================== Index Management ====================
-- Добавление индексов на всех шардах одной командой

ALTER TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster'
    ADD INDEX IF NOT EXISTS idx_session_id session_id TYPE bloom_filter GRANULARITY 1;

ALTER TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster'
    ADD INDEX IF NOT EXISTS idx_country country TYPE set(100) GRANULARITY 1;

-- Материализация индексов
ALTER TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster'
    MATERIALIZE INDEX idx_session_id;

ALTER TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster'
    MATERIALIZE INDEX idx_country;


-- ==================== Partitions Management ====================
-- Удаление старых партиций на всех шардах

-- Удалить партицию за январь 2024
ALTER TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster'
    DROP PARTITION '202401';

-- Оптимизация таблиц (объединение мелких частей)
OPTIMIZE TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster' FINAL;

-- Удаление старых данных (старше 90 дней)
ALTER TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster'
    DELETE WHERE event_time < now() - INTERVAL 90 DAY;


-- ==================== Monitoring Queries ====================

-- Информация о кластере
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';

-- Размер таблиц по шардам
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE active AND database = 'mydb'
GROUP BY database, table;

-- Проверка доступности всех шардов
SELECT
    shard_num,
    host_name,
    port,
    errors_count,
    estimated_recovery_time
FROM system.clusters
WHERE cluster = 'dwh_sharded_cluster';

-- Текущие распределенные DDL задачи
SELECT
    host,
    port,
    status,
    query,
    exception
FROM system.distributed_ddl_queue
ORDER BY entry DESC
LIMIT 20;

-- Проверка ZooKeeper подключения
SELECT * FROM system.zookeeper WHERE path = '/clickhouse';


-- ==================== Advanced: Table with Custom Sharding ====================

-- Пример таблицы с собственной функцией шардирования
CREATE TABLE IF NOT EXISTS mydb.orders_local ON CLUSTER 'dwh_sharded_cluster' (
    order_id UUID,
    user_id UInt64,
    product_id UInt64,
    order_date DateTime,
    amount Decimal(10, 2),
    status LowCardinality(String),
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (user_id, order_date);

-- Distributed таблица с шардированием по order_id
CREATE TABLE IF NOT EXISTS mydb.orders_distributed AS mydb.orders_local
ENGINE = Distributed(
    'dwh_sharded_cluster',
    'mydb',
    'orders_local',
    sipHash64(order_id)  -- Шардирование по order_id вместо user_id
);


-- ==================== Useful System Queries ====================

-- Использование дисков на всех шардах
SELECT
    hostName() as host,
    name,
    path,
    formatReadableSize(free_space) as free,
    formatReadableSize(total_space) as total,
    toString(round(free_space / total_space * 100, 2)) || '%' as free_percentage
FROM clusterAllReplicas('dwh_sharded_cluster', system.disks);

-- Текущие запросы на всех шардах
SELECT
    hostName() as host,
    query_id,
    user,
    query,
    elapsed,
    formatReadableSize(memory_usage) as memory
FROM clusterAllReplicas('dwh_sharded_cluster', system.processes)
ORDER BY elapsed DESC;

-- Медленные запросы (последние 24 часа) на всех шардах
SELECT
    hostName() as host,
    query,
    type,
    query_duration_ms,
    formatReadableSize(read_bytes) as read,
    result_rows
FROM clusterAllReplicas('dwh_sharded_cluster', system.query_log)
WHERE event_date >= today() - 1
  AND type = 'QueryFinish'
  AND query_duration_ms > 1000
ORDER BY query_duration_ms DESC
LIMIT 20;


-- ==================== Drop Tables (Clean Up) ====================
-- Удаление всех созданных объектов

-- Удалить Distributed таблицы (только на текущем шарде)
DROP TABLE IF EXISTS mydb.events_distributed;
DROP TABLE IF EXISTS mydb.events_by_hour_distributed;
DROP TABLE IF EXISTS mydb.orders_distributed;

-- Удалить локальные таблицы на всех шардах
DROP TABLE IF EXISTS mydb.events_local ON CLUSTER 'dwh_sharded_cluster';
DROP TABLE IF EXISTS mydb.events_by_hour_local ON CLUSTER 'dwh_sharded_cluster';
DROP TABLE IF EXISTS mydb.orders_local ON CLUSTER 'dwh_sharded_cluster';

-- Удалить материализованное представление
DROP VIEW IF EXISTS mydb.events_by_hour_mv ON CLUSTER 'dwh_sharded_cluster';

-- Удалить пользователей
DROP USER IF EXISTS readonly_user ON CLUSTER 'dwh_sharded_cluster';
DROP USER IF EXISTS writer_user ON CLUSTER 'dwh_sharded_cluster';
DROP USER IF EXISTS analyst ON CLUSTER 'dwh_sharded_cluster';

-- Удалить квоту
DROP QUOTA IF EXISTS analyst_quota ON CLUSTER 'dwh_sharded_cluster';

-- Удалить базу данных
DROP DATABASE IF EXISTS mydb ON CLUSTER 'dwh_sharded_cluster';


-- ==================== Notes ====================
-- ✅ С ZooKeeper можно использовать ON CLUSTER для DDL
-- ✅ Один скрипт автоматически выполняется на всех шардах
-- ✅ Distributed таблицы создаются только на одном шарде
-- ✅ Локальные таблицы создаются на всех шардах автоматически
-- ✅ Используйте sipHash64() для равномерного распределения данных
-- ⚠️ Без репликации: при отказе одного шарда теряется часть данных
-- 💡 Для production добавьте репликацию внутри каждого шарда
