-- =========================================
-- ДЕМО ТАБЛИЦЫ (УПРОЩЕННАЯ ВЕРСИЯ)
-- Только создание структуры без вставки данных
-- =========================================

-- ==================== 1. Создать базу данных ====================
CREATE DATABASE IF NOT EXISTS demo ON CLUSTER 'dwh_sharded_cluster';

-- ==================== 2. Таблица пользователей ====================

CREATE TABLE IF NOT EXISTS demo.users_local ON CLUSTER 'dwh_sharded_cluster' (
    user_id UInt64,
    username String,
    email String,
    first_name String,
    last_name String,
    city LowCardinality(String),
    country LowCardinality(String),
    registration_date DateTime,
    last_login DateTime,
    is_active UInt8,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(registration_date)
ORDER BY (user_id, registration_date);

CREATE TABLE IF NOT EXISTS demo.users_distributed AS demo.users_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'users_local', sipHash64(user_id));


-- ==================== 3. Таблица заказов ====================

CREATE TABLE IF NOT EXISTS demo.orders_local ON CLUSTER 'dwh_sharded_cluster' (
    order_id UUID,
    user_id UInt64,
    product_id UInt32,
    product_name String,
    category LowCardinality(String),
    quantity UInt32,
    price Decimal(10, 2),
    total_amount Decimal(10, 2),
    order_status LowCardinality(String),
    order_date DateTime,
    payment_method LowCardinality(String),
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(order_date)
ORDER BY (user_id, order_date, order_id);

CREATE TABLE IF NOT EXISTS demo.orders_distributed AS demo.orders_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'orders_local', sipHash64(user_id));


-- ==================== 4. Таблица событий ====================

CREATE TABLE IF NOT EXISTS demo.events_local ON CLUSTER 'dwh_sharded_cluster' (
    event_id UUID,
    user_id UInt64,
    session_id String,
    event_type LowCardinality(String),
    page_url String,
    country LowCardinality(String),
    device_type LowCardinality(String),
    browser LowCardinality(String),
    event_time DateTime,
    duration_seconds UInt32,
    created_at DateTime DEFAULT now(),

    INDEX idx_session session_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_event_type event_type TYPE set(100) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time, event_id);

CREATE TABLE IF NOT EXISTS demo.events_distributed AS demo.events_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'events_local', sipHash64(user_id));


-- ==================== 5. Проверка созданных таблиц ====================

SHOW TABLES FROM demo;

SELECT
    table,
    engine,
    create_table_query
FROM system.tables
WHERE database = 'demo'
FORMAT Vertical;
