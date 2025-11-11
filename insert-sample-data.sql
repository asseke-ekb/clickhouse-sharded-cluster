-- =========================================
-- ВСТАВКА ТЕСТОВЫХ ДАННЫХ (МАЛЫЕ ПОРЦИИ)
-- Выполняйте по одному блоку за раз
-- =========================================

-- Сначала убедитесь, что таблицы созданы:
-- Выполните demo-tables-simple.sql

-- ==================== Вставка пользователей (10 записей) ====================
-- Выполните этот блок отдельно

INSERT INTO demo.users_distributed VALUES
(1, 'user_1', 'user1@example.com', 'John', 'Smith', 'New York', 'USA', '2024-01-15 10:00:00', '2025-01-10 15:30:00', 1, now()),
(2, 'user_2', 'user2@example.com', 'Jane', 'Johnson', 'London', 'UK', '2024-02-20 11:00:00', '2025-01-11 14:20:00', 1, now()),
(3, 'user_3', 'user3@example.com', 'Bob', 'Williams', 'Toronto', 'Canada', '2024-03-10 09:00:00', '2025-01-09 16:45:00', 1, now()),
(4, 'user_4', 'user4@example.com', 'Alice', 'Brown', 'Berlin', 'Germany', '2024-04-05 12:00:00', '2025-01-08 11:15:00', 1, now()),
(5, 'user_5', 'user5@example.com', 'Mike', 'Jones', 'Paris', 'France', '2024-05-12 08:00:00', '2025-01-12 09:30:00', 1, now()),
(6, 'user_6', 'user6@example.com', 'Sarah', 'Garcia', 'Madrid', 'Spain', '2024-06-18 13:00:00', '2025-01-11 18:00:00', 1, now()),
(7, 'user_7', 'user7@example.com', 'Tom', 'Miller', 'Rome', 'Italy', '2024-07-22 14:00:00', '2025-01-10 12:45:00', 1, now()),
(8, 'user_8', 'user8@example.com', 'Emma', 'Davis', 'Amsterdam', 'Netherlands', '2024-08-30 10:00:00', '2025-01-09 10:20:00', 1, now()),
(9, 'user_9', 'user9@example.com', 'Chris', 'Wilson', 'Tokyo', 'Japan', '2024-09-14 11:00:00', '2025-01-12 19:00:00', 0, now()),
(10, 'user_10', 'user10@example.com', 'Lisa', 'Moore', 'Sydney', 'Australia', '2024-10-25 15:00:00', '2025-01-11 08:30:00', 1, now());


-- ==================== Проверка пользователей ====================
-- Выполните этот блок отдельно

SELECT count() as total_users FROM demo.users_distributed;

SELECT
    _shard_num as shard,
    count() as users_on_shard
FROM demo.users_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

SELECT * FROM demo.users_distributed LIMIT 5;


-- ==================== Вставка заказов (15 записей) ====================
-- Выполните этот блок отдельно

INSERT INTO demo.orders_distributed VALUES
(generateUUIDv4(), 1, 101, 'Laptop', 'Electronics', 1, 999.99, 999.99, 'delivered', '2025-01-05 14:30:00', 'credit_card', now()),
(generateUUIDv4(), 1, 102, 'Mouse', 'Accessories', 2, 29.99, 59.98, 'delivered', '2025-01-05 14:35:00', 'credit_card', now()),
(generateUUIDv4(), 2, 103, 'Keyboard', 'Accessories', 1, 79.99, 79.99, 'shipped', '2025-01-08 10:15:00', 'paypal', now()),
(generateUUIDv4(), 2, 104, 'Monitor', 'Electronics', 1, 349.99, 349.99, 'processing', '2025-01-10 16:20:00', 'credit_card', now()),
(generateUUIDv4(), 3, 105, 'Headphones', 'Audio', 1, 149.99, 149.99, 'delivered', '2025-01-03 11:45:00', 'bank_transfer', now()),
(generateUUIDv4(), 3, 106, 'Webcam', 'Video', 1, 89.99, 89.99, 'delivered', '2025-01-04 09:30:00', 'credit_card', now()),
(generateUUIDv4(), 4, 107, 'Speaker', 'Audio', 2, 59.99, 119.98, 'shipped', '2025-01-09 13:00:00', 'paypal', now()),
(generateUUIDv4(), 5, 108, 'Tablet', 'Electronics', 1, 499.99, 499.99, 'pending', '2025-01-11 15:45:00', 'credit_card', now()),
(generateUUIDv4(), 5, 109, 'Cable', 'Accessories', 3, 9.99, 29.97, 'delivered', '2025-01-06 12:20:00', 'credit_card', now()),
(generateUUIDv4(), 6, 110, 'Charger', 'Accessories', 1, 24.99, 24.99, 'delivered', '2025-01-07 10:00:00', 'paypal', now()),
(generateUUIDv4(), 7, 111, 'Smartphone', 'Electronics', 1, 799.99, 799.99, 'cancelled', '2025-01-02 14:15:00', 'credit_card', now()),
(generateUUIDv4(), 8, 112, 'Stand', 'Accessories', 1, 39.99, 39.99, 'delivered', '2025-01-08 11:30:00', 'bank_transfer', now()),
(generateUUIDv4(), 9, 113, 'Adapter', 'Accessories', 2, 14.99, 29.98, 'processing', '2025-01-10 09:45:00', 'paypal', now()),
(generateUUIDv4(), 10, 114, 'Battery', 'Accessories', 1, 19.99, 19.99, 'shipped', '2025-01-09 16:00:00', 'credit_card', now()),
(generateUUIDv4(), 10, 115, 'Case', 'Accessories', 1, 34.99, 34.99, 'delivered', '2025-01-05 13:20:00', 'paypal', now());


-- ==================== Проверка заказов ====================
-- Выполните этот блок отдельно

SELECT count() as total_orders FROM demo.orders_distributed;

SELECT
    _shard_num as shard,
    count() as orders_on_shard,
    sum(total_amount) as revenue_on_shard
FROM demo.orders_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

SELECT
    order_id,
    user_id,
    product_name,
    total_amount,
    order_status,
    order_date
FROM demo.orders_distributed
ORDER BY order_date DESC
LIMIT 10;


-- ==================== Вставка событий (20 записей) ====================
-- Выполните этот блок отдельно

INSERT INTO demo.events_distributed VALUES
(generateUUIDv4(), 1, 'session_001', 'page_view', 'https://shop.com/home', 'USA', 'desktop', 'Chrome', '2025-01-11 10:00:00', 45, now()),
(generateUUIDv4(), 1, 'session_001', 'click', 'https://shop.com/products', 'USA', 'desktop', 'Chrome', '2025-01-11 10:01:30', 120, now()),
(generateUUIDv4(), 1, 'session_001', 'purchase', 'https://shop.com/checkout', 'USA', 'desktop', 'Chrome', '2025-01-11 10:15:00', 300, now()),
(generateUUIDv4(), 2, 'session_002', 'page_view', 'https://shop.com/home', 'UK', 'mobile', 'Safari', '2025-01-11 14:30:00', 30, now()),
(generateUUIDv4(), 2, 'session_002', 'click', 'https://shop.com/about', 'UK', 'mobile', 'Safari', '2025-01-11 14:32:00', 60, now()),
(generateUUIDv4(), 3, 'session_003', 'page_view', 'https://shop.com/products', 'Canada', 'tablet', 'Chrome', '2025-01-10 16:00:00', 90, now()),
(generateUUIDv4(), 3, 'session_003', 'add_to_cart', 'https://shop.com/cart', 'Canada', 'tablet', 'Chrome', '2025-01-10 16:05:00', 45, now()),
(generateUUIDv4(), 4, 'session_004', 'page_view', 'https://shop.com/home', 'Germany', 'desktop', 'Firefox', '2025-01-12 09:00:00', 55, now()),
(generateUUIDv4(), 4, 'session_004', 'search', 'https://shop.com/search', 'Germany', 'desktop', 'Firefox', '2025-01-12 09:03:00', 30, now()),
(generateUUIDv4(), 5, 'session_005', 'page_view', 'https://shop.com/blog', 'France', 'mobile', 'Chrome', '2025-01-11 11:00:00', 120, now()),
(generateUUIDv4(), 5, 'session_005', 'click', 'https://shop.com/contact', 'France', 'mobile', 'Chrome', '2025-01-11 11:05:00', 40, now()),
(generateUUIDv4(), 6, 'session_006', 'page_view', 'https://shop.com/products', 'Spain', 'desktop', 'Edge', '2025-01-10 18:00:00', 75, now()),
(generateUUIDv4(), 6, 'session_006', 'click', 'https://shop.com/cart', 'Spain', 'desktop', 'Edge', '2025-01-10 18:10:00', 90, now()),
(generateUUIDv4(), 7, 'session_007', 'page_view', 'https://shop.com/home', 'Italy', 'mobile', 'Safari', '2025-01-09 12:00:00', 35, now()),
(generateUUIDv4(), 8, 'session_008', 'page_view', 'https://shop.com/products', 'Netherlands', 'desktop', 'Chrome', '2025-01-11 15:30:00', 60, now()),
(generateUUIDv4(), 8, 'session_008', 'add_to_cart', 'https://shop.com/cart', 'Netherlands', 'desktop', 'Chrome', '2025-01-11 15:35:00', 50, now()),
(generateUUIDv4(), 9, 'session_009', 'page_view', 'https://shop.com/home', 'Japan', 'mobile', 'Chrome', '2025-01-12 19:00:00', 40, now()),
(generateUUIDv4(), 9, 'session_009', 'signup', 'https://shop.com/register', 'Japan', 'mobile', 'Chrome', '2025-01-12 19:05:00', 180, now()),
(generateUUIDv4(), 10, 'session_010', 'page_view', 'https://shop.com/products', 'Australia', 'tablet', 'Safari', '2025-01-10 08:00:00', 95, now()),
(generateUUIDv4(), 10, 'session_010', 'purchase', 'https://shop.com/checkout', 'Australia', 'tablet', 'Safari', '2025-01-10 08:20:00', 240, now());


-- ==================== Проверка событий ====================
-- Выполните этот блок отдельно

SELECT count() as total_events FROM demo.events_distributed;

SELECT
    _shard_num as shard,
    count() as events_on_shard,
    uniq(user_id) as unique_users
FROM demo.events_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

SELECT
    event_type,
    count() as events,
    uniq(user_id) as unique_users
FROM demo.events_distributed
GROUP BY event_type
ORDER BY events DESC;


-- ==================== Аналитические запросы ====================
-- Выполняйте по одному

-- Топ пользователей по выручке
SELECT
    u.user_id,
    u.username,
    u.country,
    count(o.order_id) as orders,
    sum(o.total_amount) as total_spent
FROM demo.orders_distributed o
JOIN demo.users_distributed u ON o.user_id = u.user_id
GROUP BY u.user_id, u.username, u.country
ORDER BY total_spent DESC;

-- Статистика по странам
SELECT
    country,
    count() as events,
    uniq(user_id) as users,
    countIf(event_type = 'purchase') as purchases
FROM demo.events_distributed
GROUP BY country
ORDER BY events DESC;

-- Воронка конверсии
SELECT
    event_type,
    count() as events,
    uniq(user_id) as unique_users
FROM demo.events_distributed
WHERE event_type IN ('page_view', 'add_to_cart', 'purchase')
GROUP BY event_type
ORDER BY
    CASE event_type
        WHEN 'page_view' THEN 1
        WHEN 'add_to_cart' THEN 2
        WHEN 'purchase' THEN 3
    END;

-- Размер таблиц
SELECT
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as total_rows
FROM system.parts
WHERE database = 'demo' AND active
GROUP BY table
ORDER BY sum(bytes) DESC;
