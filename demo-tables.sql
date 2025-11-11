-- =========================================
-- ДЕМО ТАБЛИЦЫ И ДАННЫЕ ДЛЯ ТЕСТИРОВАНИЯ
-- ClickHouse Sharded Cluster
-- =========================================

-- ==================== 1. Создать базу данных ====================
CREATE DATABASE IF NOT EXISTS demo ON CLUSTER 'dwh_sharded_cluster';

-- ==================== 2. Таблица пользователей ====================

-- Локальная таблица на каждом шарде
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

-- Distributed таблица (создать на текущем шарде)
CREATE TABLE IF NOT EXISTS demo.users_distributed AS demo.users_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'users_local', sipHash64(user_id));


-- ==================== 3. Таблица заказов ====================

-- Локальная таблица на каждом шарде
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

-- Distributed таблица
CREATE TABLE IF NOT EXISTS demo.orders_distributed AS demo.orders_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'orders_local', sipHash64(user_id));


-- ==================== 4. Таблица событий (веб-аналитика) ====================

-- Локальная таблица на каждом шарде
CREATE TABLE IF NOT EXISTS demo.events_local ON CLUSTER 'dwh_sharded_cluster' (
    event_id UUID,
    user_id UInt64,
    session_id String,
    event_type LowCardinality(String),
    page_url String,
    referrer String,
    user_agent String,
    ip_address String,
    country LowCardinality(String),
    city LowCardinality(String),
    device_type LowCardinality(String),
    browser LowCardinality(String),
    event_time DateTime,
    duration_seconds UInt32,
    created_at DateTime DEFAULT now(),

    -- Индексы для быстрого поиска
    INDEX idx_session session_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_event_type event_type TYPE set(100) GRANULARITY 1,
    INDEX idx_country country TYPE set(100) GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_time)
ORDER BY (user_id, event_time, event_id);

-- Distributed таблица
CREATE TABLE IF NOT EXISTS demo.events_distributed AS demo.events_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'events_local', sipHash64(user_id));


-- ==================== 5. Агрегированная таблица (суммарные данные по дням) ====================

-- Локальная таблица на каждом шарде
CREATE TABLE IF NOT EXISTS demo.daily_stats_local ON CLUSTER 'dwh_sharded_cluster' (
    stat_date Date,
    country String,
    event_type String,
    total_events UInt64,
    unique_users UInt64,
    total_orders UInt64,
    total_revenue Decimal(15, 2)
)
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(stat_date)
ORDER BY (stat_date, country, event_type);

-- Материализованное представление для автоматической агрегации
CREATE MATERIALIZED VIEW IF NOT EXISTS demo.daily_stats_mv ON CLUSTER 'dwh_sharded_cluster'
TO demo.daily_stats_local AS
SELECT
    toDate(event_time) as stat_date,
    country,
    event_type,
    count() as total_events,
    uniq(user_id) as unique_users,
    0 as total_orders,
    0 as total_revenue
FROM demo.events_local
GROUP BY stat_date, country, event_type;

-- Distributed таблица
CREATE TABLE IF NOT EXISTS demo.daily_stats_distributed AS demo.daily_stats_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'daily_stats_local', rand());


-- ==================== 6. Генерация тестовых данных ====================

-- ===== 6.1 Пользователи (1000 записей) =====
INSERT INTO demo.users_distributed
SELECT
    number as user_id,
    concat('user_', toString(number)) as username,
    concat('user', toString(number), '@example.com') as email,
    arrayElement(['John', 'Jane', 'Bob', 'Alice', 'Mike', 'Sarah', 'Tom', 'Emma'], (number % 8) + 1) as first_name,
    arrayElement(['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis'], (number % 8) + 1) as last_name,
    arrayElement(['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego'], (number % 8) + 1) as city,
    arrayElement(['USA', 'UK', 'Canada', 'Germany', 'France', 'Spain', 'Italy', 'Netherlands'], (number % 8) + 1) as country,
    now() - INTERVAL (number % 365) DAY as registration_date,
    now() - INTERVAL (number % 7) DAY as last_login,
    if(number % 10 != 0, 1, 0) as is_active,
    now() as created_at
FROM numbers(1000);


-- ===== 6.2 Заказы (5000 записей) =====
INSERT INTO demo.orders_distributed
SELECT
    generateUUIDv4() as order_id,
    (number % 1000) as user_id,
    (number % 100) + 1 as product_id,
    arrayElement([
        'Laptop', 'Smartphone', 'Tablet', 'Headphones', 'Monitor',
        'Keyboard', 'Mouse', 'Webcam', 'Speaker', 'Charger',
        'Cable', 'Case', 'Stand', 'Adapter', 'Battery'
    ], (number % 15) + 1) as product_name,
    arrayElement(['Electronics', 'Accessories', 'Computers', 'Audio', 'Video'], (number % 5) + 1) as category,
    (number % 5) + 1 as quantity,
    round((number % 1000) + 10.5, 2) as price,
    round(((number % 5) + 1) * ((number % 1000) + 10.5), 2) as total_amount,
    arrayElement(['pending', 'processing', 'shipped', 'delivered', 'cancelled'], (number % 5) + 1) as order_status,
    now() - INTERVAL (number % 90) DAY - INTERVAL (number % 24) HOUR as order_date,
    arrayElement(['credit_card', 'paypal', 'bank_transfer', 'cash'], (number % 4) + 1) as payment_method,
    now() as created_at
FROM numbers(5000);


-- ===== 6.3 События (10000 записей) =====
INSERT INTO demo.events_distributed
SELECT
    generateUUIDv4() as event_id,
    (number % 1000) as user_id,
    concat('session_', toString(number % 500)) as session_id,
    arrayElement(['page_view', 'click', 'scroll', 'search', 'add_to_cart', 'purchase', 'signup', 'login'], (number % 8) + 1) as event_type,
    concat('https://example.com/', arrayElement(['home', 'products', 'about', 'contact', 'blog', 'cart', 'checkout'], (number % 7) + 1)) as page_url,
    if(number % 3 = 0, concat('https://google.com/search?q=', toString(number)), '') as referrer,
    concat('Mozilla/5.0 (',
           arrayElement(['Windows NT 10.0', 'Macintosh', 'X11; Linux x86_64', 'iPhone', 'iPad'], (number % 5) + 1),
           ')') as user_agent,
    concat('192.168.', toString((number % 255) + 1), '.', toString((number % 255) + 1)) as ip_address,
    arrayElement(['USA', 'UK', 'Canada', 'Germany', 'France', 'Spain', 'Italy', 'Netherlands', 'Japan', 'China'], (number % 10) + 1) as country,
    arrayElement(['New York', 'London', 'Toronto', 'Berlin', 'Paris', 'Madrid', 'Rome', 'Amsterdam', 'Tokyo', 'Beijing'], (number % 10) + 1) as city,
    arrayElement(['desktop', 'mobile', 'tablet'], (number % 3) + 1) as device_type,
    arrayElement(['Chrome', 'Firefox', 'Safari', 'Edge', 'Opera'], (number % 5) + 1) as browser,
    now() - INTERVAL (number % 30) DAY - INTERVAL (number % 24) HOUR - INTERVAL (number % 60) MINUTE as event_time,
    (number % 300) + 1 as duration_seconds,
    now() as created_at
FROM numbers(10000);


-- ==================== 7. Проверка данных ====================

-- Проверить распределение пользователей по шардам
SELECT
    _shard_num as shard,
    count() as users_count,
    uniq(country) as countries
FROM demo.users_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

-- Проверить распределение заказов по шардам
SELECT
    _shard_num as shard,
    count() as orders_count,
    sum(total_amount) as total_revenue
FROM demo.orders_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

-- Проверить распределение событий по шардам
SELECT
    _shard_num as shard,
    count() as events_count,
    uniq(user_id) as unique_users
FROM demo.events_distributed
GROUP BY _shard_num
ORDER BY _shard_num;


-- ==================== 8. Примеры аналитических запросов ====================

-- Топ 10 пользователей по количеству заказов
SELECT
    o.user_id,
    u.username,
    u.email,
    count() as order_count,
    sum(o.total_amount) as total_spent
FROM demo.orders_distributed o
LEFT JOIN demo.users_distributed u ON o.user_id = u.user_id
GROUP BY o.user_id, u.username, u.email
ORDER BY total_spent DESC
LIMIT 10;

-- Статистика по странам
SELECT
    country,
    count() as total_events,
    uniq(user_id) as unique_users,
    countIf(event_type = 'purchase') as purchases,
    countIf(event_type = 'page_view') as page_views
FROM demo.events_distributed
GROUP BY country
ORDER BY total_events DESC;

-- Динамика заказов по дням (последние 30 дней)
SELECT
    toDate(order_date) as date,
    count() as orders_count,
    sum(total_amount) as revenue,
    avg(total_amount) as avg_order_value
FROM demo.orders_distributed
WHERE order_date >= today() - INTERVAL 30 DAY
GROUP BY date
ORDER BY date DESC;

-- Воронка конверсии
SELECT
    event_type,
    count() as events,
    uniq(user_id) as unique_users,
    round(count() * 100.0 / (SELECT count() FROM demo.events_distributed), 2) as percentage
FROM demo.events_distributed
WHERE event_type IN ('page_view', 'add_to_cart', 'purchase')
GROUP BY event_type
ORDER BY
    CASE event_type
        WHEN 'page_view' THEN 1
        WHEN 'add_to_cart' THEN 2
        WHEN 'purchase' THEN 3
    END;

-- Статистика по устройствам
SELECT
    device_type,
    browser,
    count() as sessions,
    uniq(user_id) as unique_users,
    avg(duration_seconds) as avg_duration_sec
FROM demo.events_distributed
GROUP BY device_type, browser
ORDER BY sessions DESC;


-- ==================== 9. Информация о таблицах ====================

-- Размер таблиц
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as total_rows,
    count() as parts
FROM system.parts
WHERE active AND database = 'demo'
GROUP BY database, table
ORDER BY sum(bytes) DESC;

-- Список всех таблиц в базе demo
SHOW TABLES FROM demo;


-- ==================== 10. Очистка данных (если нужно) ====================

-- Удалить distributed таблицы
-- DROP TABLE IF EXISTS demo.users_distributed;
-- DROP TABLE IF EXISTS demo.orders_distributed;
-- DROP TABLE IF EXISTS demo.events_distributed;
-- DROP TABLE IF EXISTS demo.daily_stats_distributed;

-- Удалить локальные таблицы на всех шардах
-- DROP TABLE IF EXISTS demo.users_local ON CLUSTER 'dwh_sharded_cluster';
-- DROP TABLE IF EXISTS demo.orders_local ON CLUSTER 'dwh_sharded_cluster';
-- DROP TABLE IF EXISTS demo.events_local ON CLUSTER 'dwh_sharded_cluster';
-- DROP TABLE IF EXISTS demo.daily_stats_local ON CLUSTER 'dwh_sharded_cluster';
-- DROP VIEW IF EXISTS demo.daily_stats_mv ON CLUSTER 'dwh_sharded_cluster';

-- Удалить всю базу данных
-- DROP DATABASE IF EXISTS demo ON CLUSTER 'dwh_sharded_cluster';
