# Демо данные для тестирования ClickHouse кластера

## Быстрый старт

### 1. Запустите скрипт через DBeaver

Откройте файл [demo-tables.sql](demo-tables.sql) в DBeaver и выполните его целиком (Ctrl+Enter или F5).

**Или выполните через командную строку:**

```bash
cd clickhouse_shard

# Вариант 1: Через Docker
docker exec -i clickhouse-shard-01 clickhouse-client --user=dbeaver --password=dbeaver123 --multiquery < demo-tables.sql

# Вариант 2: Если clickhouse-client установлен локально
clickhouse-client --host localhost --port 9000 --user dbeaver --password dbeaver123 --multiquery < demo-tables.sql
```

---

## Что создается

### База данных: `demo`

Создается на всех 3 шардах автоматически с помощью `ON CLUSTER`.

### Таблицы (локальные + distributed):

| Таблица | Записей | Описание | Шардирование |
|---------|---------|----------|--------------|
| **users** | 1,000 | Пользователи (ID, email, имя, страна) | По user_id |
| **orders** | 5,000 | Заказы (товары, цены, статусы) | По user_id |
| **events** | 10,000 | Веб-события (клики, просмотры, покупки) | По user_id |
| **daily_stats** | auto | Агрегированная статистика по дням | Случайное |

---

## Структура таблиц

### 1. demo.users_distributed

```sql
user_id             UInt64          -- ID пользователя
username            String          -- Логин
email               String          -- Email
first_name          String          -- Имя
last_name           String          -- Фамилия
city                String          -- Город
country             String          -- Страна
registration_date   DateTime        -- Дата регистрации
last_login          DateTime        -- Последний вход
is_active           UInt8           -- Активен (1) или нет (0)
```

### 2. demo.orders_distributed

```sql
order_id            UUID            -- ID заказа
user_id             UInt64          -- ID пользователя
product_id          UInt32          -- ID товара
product_name        String          -- Название товара
category            String          -- Категория
quantity            UInt32          -- Количество
price               Decimal(10,2)   -- Цена за единицу
total_amount        Decimal(10,2)   -- Общая сумма
order_status        String          -- Статус (pending, delivered и т.д.)
order_date          DateTime        -- Дата заказа
payment_method      String          -- Способ оплаты
```

### 3. demo.events_distributed

```sql
event_id            UUID            -- ID события
user_id             UInt64          -- ID пользователя
session_id          String          -- ID сессии
event_type          String          -- Тип (page_view, click, purchase)
page_url            String          -- URL страницы
referrer            String          -- Источник перехода
user_agent          String          -- User Agent браузера
ip_address          String          -- IP адрес
country             String          -- Страна
city                String          -- Город
device_type         String          -- Устройство (desktop, mobile)
browser             String          -- Браузер
event_time          DateTime        -- Время события
duration_seconds    UInt32          -- Длительность в секундах
```

---

## Примеры запросов

### Базовые запросы

```sql
-- Количество пользователей по странам
SELECT country, count() as users
FROM demo.users_distributed
GROUP BY country
ORDER BY users DESC;

-- Топ-10 самых дорогих заказов
SELECT
    order_id,
    user_id,
    product_name,
    total_amount,
    order_date
FROM demo.orders_distributed
ORDER BY total_amount DESC
LIMIT 10;

-- События за последние 7 дней
SELECT
    event_type,
    count() as events,
    uniq(user_id) as unique_users
FROM demo.events_distributed
WHERE event_time >= now() - INTERVAL 7 DAY
GROUP BY event_type
ORDER BY events DESC;
```

### Распределение данных по шардам

```sql
-- Проверить, на каких шардах какие данные
SELECT
    _shard_num as shard,
    count() as rows,
    formatReadableSize(sum(bytes)) as size
FROM demo.users_distributed
GROUP BY _shard_num
ORDER BY _shard_num;

-- То же для заказов
SELECT
    _shard_num as shard,
    count() as orders,
    sum(total_amount) as revenue
FROM demo.orders_distributed
GROUP BY _shard_num;

-- То же для событий
SELECT
    _shard_num as shard,
    count() as events,
    uniq(user_id) as users
FROM demo.events_distributed
GROUP BY _shard_num;
```

### Аналитические запросы

```sql
-- Топ-10 пользователей по выручке
SELECT
    u.user_id,
    u.username,
    u.email,
    u.country,
    count(o.order_id) as orders,
    sum(o.total_amount) as total_spent
FROM demo.orders_distributed o
JOIN demo.users_distributed u ON o.user_id = u.user_id
GROUP BY u.user_id, u.username, u.email, u.country
ORDER BY total_spent DESC
LIMIT 10;

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

-- Средний чек по странам
SELECT
    u.country,
    count(o.order_id) as orders,
    sum(o.total_amount) as revenue,
    avg(o.total_amount) as avg_order_value
FROM demo.orders_distributed o
JOIN demo.users_distributed u ON o.user_id = u.user_id
GROUP BY u.country
ORDER BY revenue DESC;

-- RFM анализ (Recency, Frequency, Monetary)
SELECT
    user_id,
    dateDiff('day', max(order_date), now()) as days_since_last_order,
    count() as order_frequency,
    sum(total_amount) as total_monetary_value
FROM demo.orders_distributed
GROUP BY user_id
ORDER BY total_monetary_value DESC
LIMIT 20;
```

### Временные ряды

```sql
-- Динамика заказов по дням
SELECT
    toDate(order_date) as date,
    count() as orders,
    sum(total_amount) as revenue,
    uniq(user_id) as unique_users
FROM demo.orders_distributed
WHERE order_date >= today() - INTERVAL 30 DAY
GROUP BY date
ORDER BY date DESC;

-- Почасовая активность событий
SELECT
    toHour(event_time) as hour,
    count() as events
FROM demo.events_distributed
WHERE event_time >= today() - INTERVAL 7 DAY
GROUP BY hour
ORDER BY hour;
```

### Агрегации и группировки

```sql
-- Статистика по категориям товаров
SELECT
    category,
    count() as orders,
    sum(quantity) as units_sold,
    sum(total_amount) as revenue,
    avg(price) as avg_price
FROM demo.orders_distributed
GROUP BY category
ORDER BY revenue DESC;

-- Статистика по устройствам
SELECT
    device_type,
    browser,
    count() as events,
    uniq(user_id) as users,
    avg(duration_seconds) as avg_duration
FROM demo.events_distributed
GROUP BY device_type, browser
ORDER BY events DESC;

-- Распределение пользователей по активности
SELECT
    if(is_active = 1, 'Active', 'Inactive') as status,
    country,
    count() as users
FROM demo.users_distributed
GROUP BY status, country
ORDER BY users DESC;
```

---

## Проверка размера данных

```sql
-- Размер всех таблиц в базе demo
SELECT
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    count() as parts
FROM system.parts
WHERE database = 'demo' AND active
GROUP BY table
ORDER BY sum(bytes) DESC;

-- Детальная информация по партициям
SELECT
    table,
    partition,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows
FROM system.parts
WHERE database = 'demo' AND active
GROUP BY table, partition
ORDER BY table, partition;
```

---

## Где какие данные лежат

### Проверка локальных таблиц на каждом шарде

Подключитесь к каждому шарду отдельно:

#### Shard-1 (localhost:8123)

```sql
-- Локальные данные на Shard-1
SELECT 'users' as table, count() as rows FROM demo.users_local
UNION ALL
SELECT 'orders', count() FROM demo.orders_local
UNION ALL
SELECT 'events', count() FROM demo.events_local;
```

#### Shard-2 (localhost:8124)

```sql
-- Локальные данные на Shard-2
SELECT 'users' as table, count() as rows FROM demo.users_local
UNION ALL
SELECT 'orders', count() FROM demo.orders_local
UNION ALL
SELECT 'events', count() FROM demo.events_local;
```

#### Shard-3 (localhost:8125)

```sql
-- Локальные данные на Shard-3
SELECT 'users' as table, count() as rows FROM demo.users_local
UNION ALL
SELECT 'orders', count() FROM demo.orders_local
UNION ALL
SELECT 'events', count() FROM demo.events_local;
```

### Или через один запрос ко всем шардам:

```sql
SELECT
    hostName() as shard,
    'users' as table,
    count() as rows
FROM clusterAllReplicas('dwh_sharded_cluster', demo.users_local)
GROUP BY shard, table
UNION ALL
SELECT
    hostName() as shard,
    'orders' as table,
    count() as rows
FROM clusterAllReplicas('dwh_sharded_cluster', demo.orders_local)
GROUP BY shard, table
UNION ALL
SELECT
    hostName() as shard,
    'events' as table,
    count() as rows
FROM clusterAllReplicas('dwh_sharded_cluster', demo.events_local)
GROUP BY shard, table
ORDER BY table, shard;
```

---

## Дополнительные генераторы данных

### Добавить еще пользователей

```sql
INSERT INTO demo.users_distributed
SELECT
    number + 1000 as user_id,
    concat('new_user_', toString(number)) as username,
    concat('newuser', toString(number), '@test.com') as email,
    arrayElement(['Alex', 'Maria', 'Chris', 'Linda'], (number % 4) + 1) as first_name,
    arrayElement(['Taylor', 'Anderson', 'Thomas', 'Moore'], (number % 4) + 1) as last_name,
    arrayElement(['Moscow', 'Tokyo', 'Paris', 'Berlin'], (number % 4) + 1) as city,
    arrayElement(['Russia', 'Japan', 'France', 'Germany'], (number % 4) + 1) as country,
    now() - INTERVAL (number % 180) DAY as registration_date,
    now() - INTERVAL (number % 3) DAY as last_login,
    1 as is_active,
    now() as created_at
FROM numbers(500);
```

### Добавить больше событий

```sql
INSERT INTO demo.events_distributed
SELECT
    generateUUIDv4() as event_id,
    (number % 1500) as user_id,
    concat('session_', toString(number % 1000)) as session_id,
    arrayElement(['page_view', 'click', 'purchase'], (number % 3) + 1) as event_type,
    concat('https://shop.com/product/', toString(number % 100)) as page_url,
    '' as referrer,
    'Mozilla/5.0' as user_agent,
    concat('10.0.', toString(number % 255), '.1') as ip_address,
    arrayElement(['USA', 'UK', 'Germany'], (number % 3) + 1) as country,
    arrayElement(['New York', 'London', 'Berlin'], (number % 3) + 1) as city,
    arrayElement(['mobile', 'desktop'], (number % 2) + 1) as device_type,
    'Chrome' as browser,
    now() - INTERVAL (number % 12) HOUR as event_time,
    (number % 120) + 10 as duration_seconds,
    now() as created_at
FROM numbers(5000);
```

---

## Очистка данных

### Удалить данные из таблиц (локально на каждом шарде)

```sql
-- Очистить таблицы (быстро, но удаляет партиции)
TRUNCATE TABLE demo.users_local ON CLUSTER 'dwh_sharded_cluster';
TRUNCATE TABLE demo.orders_local ON CLUSTER 'dwh_sharded_cluster';
TRUNCATE TABLE demo.events_local ON CLUSTER 'dwh_sharded_cluster';
```

### Удалить таблицы

```sql
-- Удалить distributed таблицы (на текущем шарде)
DROP TABLE IF EXISTS demo.users_distributed;
DROP TABLE IF EXISTS demo.orders_distributed;
DROP TABLE IF EXISTS demo.events_distributed;
DROP TABLE IF EXISTS demo.daily_stats_distributed;

-- Удалить локальные таблицы на всех шардах
DROP TABLE IF EXISTS demo.users_local ON CLUSTER 'dwh_sharded_cluster';
DROP TABLE IF EXISTS demo.orders_local ON CLUSTER 'dwh_sharded_cluster';
DROP TABLE IF EXISTS demo.events_local ON CLUSTER 'dwh_sharded_cluster';
DROP TABLE IF EXISTS demo.daily_stats_local ON CLUSTER 'dwh_sharded_cluster';
DROP VIEW IF EXISTS demo.daily_stats_mv ON CLUSTER 'dwh_sharded_cluster';
```

### Удалить всю базу данных

```sql
DROP DATABASE IF EXISTS demo ON CLUSTER 'dwh_sharded_cluster';
```

---

## Подключение к шардам в DBeaver

### Вариант 1: Одно подключение к Shard-1 (рекомендуется)

```
Host: localhost
Port: 8123
User: dbeaver
Password: dbeaver123
Database: demo
```

Через это подключение вы работаете с **distributed** таблицами и видите данные со всех 3 шардов.

### Вариант 2: Отдельные подключения к каждому шарду

Создайте 3 подключения:

**Shard-1:**
```
Host: localhost, Port: 8123, Database: demo
```

**Shard-2:**
```
Host: localhost, Port: 8124, Database: demo
```

**Shard-3:**
```
Host: localhost, Port: 8125, Database: demo
```

В каждом подключении используйте `demo.users_local`, `demo.orders_local` для просмотра **локальных данных на конкретном шарде**.

---

## Полезные системные запросы

```sql
-- Список всех баз данных
SHOW DATABASES;

-- Список таблиц в базе demo
SHOW TABLES FROM demo;

-- Структура таблицы
DESCRIBE demo.users_distributed;

-- Информация о кластере
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';

-- Текущие запросы
SELECT query_id, user, query, elapsed FROM system.processes;

-- История запросов (последние 10)
SELECT
    type,
    query_duration_ms,
    query,
    result_rows
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 10;
```

---

**Готово!** Теперь у вас есть демо-данные для тестирования шардированного ClickHouse кластера. 🚀

**Файлы:**
- [demo-tables.sql](demo-tables.sql) - скрипт создания таблиц и данных
- [DBEAVER-CONNECTION.md](DBEAVER-CONNECTION.md) - инструкция по подключению
- [QUICK-START.md](QUICK-START.md) - быстрый старт кластера
