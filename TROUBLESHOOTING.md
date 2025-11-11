# Решение проблемы с вставкой данных

## Проблема

При выполнении больших INSERT запросов в DBeaver возникает ошибка:
```
Code: 1001. DB::Exception: <Unreadable error message> (transport error: 500)
```

**Причина:** Проблема с правами доступа к директориям данных ClickHouse на Windows при использовании Docker bind mounts.

---

## ✅ Решение: Используйте упрощенный подход

### Шаг 1: Создайте структуру таблиц

Выполните файл **[demo-tables-simple.sql](demo-tables-simple.sql)** в DBeaver:

1. Откройте файл в DBeaver
2. Выполните весь скрипт (F5)
3. Это создаст 3 таблицы (users, orders, events) **БЕЗ данных**

### Шаг 2: Вставьте данные малыми порциями

Откройте файл **[insert-sample-data.sql](insert-sample-data.sql)** и выполняйте **по одному блоку**:

#### Блок 1: Вставка пользователей (10 записей)

```sql
INSERT INTO demo.users_distributed VALUES
(1, 'user_1', 'user1@example.com', 'John', 'Smith', 'New York', 'USA', ...),
(2, 'user_2', 'user2@example.com', 'Jane', 'Johnson', 'London', 'UK', ...),
...
```

✅ Выделите **ТОЛЬКО этот блок** → Ctrl+Enter

#### Блок 2: Проверка пользователей

```sql
SELECT count() as total_users FROM demo.users_distributed;

SELECT _shard_num, count() FROM demo.users_distributed GROUP BY _shard_num;
```

✅ Выполните отдельно

#### Блок 3: Вставка заказов (15 записей)

```sql
INSERT INTO demo.orders_distributed VALUES
(generateUUIDv4(), 1, 101, 'Laptop', ...),
...
```

✅ Выделите **ТОЛЬКО этот блок** → Ctrl+Enter

#### Блок 4: Вставка событий (20 записей)

```sql
INSERT INTO demo.events_distributed VALUES
(generateUUIDv4(), 1, 'session_001', 'page_view', ...),
...
```

✅ Выделите **ТОЛЬКО этот блок** → Ctrl+Enter

---

## 📊 После успешной вставки

### Проверьте данные:

```sql
-- Общее количество
SELECT 'users' as table, count() as rows FROM demo.users_distributed
UNION ALL
SELECT 'orders', count() FROM demo.orders_distributed
UNION ALL
SELECT 'events', count() FROM demo.events_distributed;

-- Распределение по шардам
SELECT
    _shard_num as shard,
    'users' as table,
    count() as rows
FROM demo.users_distributed
GROUP BY _shard_num;
```

### Топ пользователей по выручке:

```sql
SELECT
    u.username,
    u.country,
    count(o.order_id) as orders,
    sum(o.total_amount) as total_spent
FROM demo.orders_distributed o
JOIN demo.users_distributed u ON o.user_id = u.user_id
GROUP BY u.username, u.country
ORDER BY total_spent DESC;
```

---

## 🔧 Альтернативные способы вставки данных

### Способ 1: Через Docker (обходит проблему прав)

```bash
# Создать файл с SQL командами
cat > insert.sql << 'EOF'
INSERT INTO demo.users_distributed VALUES
(1, 'user_1', 'user1@example.com', 'John', 'Smith', 'New York', 'USA', '2024-01-15 10:00:00', '2025-01-10 15:30:00', 1, now());
EOF

# Выполнить через Docker
docker exec -i clickhouse-shard-01 clickhouse-client --user=dbeaver --password=dbeaver123 < insert.sql
```

### Способ 2: Маленькие порции (по 1 записи)

В DBeaver выполняйте по одной записи за раз:

```sql
INSERT INTO demo.users_distributed VALUES
(1, 'user_1', 'user1@example.com', 'John', 'Smith', 'New York', 'USA', '2024-01-15 10:00:00', '2025-01-10 15:30:00', 1, now());

-- Проверить
SELECT * FROM demo.users_distributed WHERE user_id = 1;

-- Следующая запись
INSERT INTO demo.users_distributed VALUES
(2, 'user_2', 'user2@example.com', 'Jane', 'Johnson', 'London', 'UK', '2024-02-20 11:00:00', '2025-01-11 14:20:00', 1, now());
```

### Способ 3: Использовать SELECT вместо VALUES

```sql
-- Вместо INSERT INTO ... VALUES
-- Используйте INSERT INTO ... SELECT

INSERT INTO demo.users_distributed
SELECT
    number as user_id,
    concat('user_', toString(number)) as username,
    concat('user', toString(number), '@example.com') as email,
    'John' as first_name,
    'Smith' as last_name,
    'New York' as city,
    'USA' as country,
    now() - INTERVAL number DAY as registration_date,
    now() as last_login,
    1 as is_active,
    now() as created_at
FROM numbers(5);  -- Только 5 записей за раз
```

---

## ⚠️ Что НЕ РАБОТАЕТ на Windows

❌ Большие INSERT с тысячами записей
❌ INSERT ... FROM numbers(10000)
❌ Вставка через HTTP протокол с большими данными

## ✅ Что РАБОТАЕТ

✅ Создание таблиц с ON CLUSTER
✅ SELECT запросы (любого размера)
✅ Маленькие INSERT (до 20-50 записей за раз)
✅ JOIN, GROUP BY, агрегации
✅ Все читающие операции

---

## 🎯 Рекомендации

1. **Для демонстрации шардирования** используйте [insert-sample-data.sql](insert-sample-data.sql) - выполняйте блоками
2. **Для production** используйте Linux/macOS или Docker volumes вместо bind mounts
3. **Для тестирования** достаточно 10-50 записей, чтобы увидеть распределение по шардам

---

## 📁 Файлы для использования

| Файл | Назначение | Когда использовать |
|------|------------|-------------------|
| [demo-tables-simple.sql](demo-tables-simple.sql) | Только структура таблиц | Выполнить первым |
| [insert-sample-data.sql](insert-sample-data.sql) | Вставка по блокам | Выполнять блоками |
| [demo-tables.sql](demo-tables.sql) | Полная версия (не работает на Windows) | Только для Linux/Docker volumes |

---

## ✅ Быстрая проверка работоспособности

После создания таблиц и вставки данных:

```sql
-- 1. Проверить кластер
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';

-- 2. Проверить таблицы
SHOW TABLES FROM demo;

-- 3. Проверить данные
SELECT count() FROM demo.users_distributed;

-- 4. Проверить распределение по шардам
SELECT _shard_num, count() FROM demo.users_distributed GROUP BY _shard_num;

-- 5. Если видите данные на всех 3 шардах - всё работает! ✅
```

---

## 🚀 Следующие шаги

После успешной вставки данных вы можете:

1. Экспериментировать с аналитическими запросами
2. Проверять производительность JOIN операций
3. Смотреть, как данные распределяются по шардам
4. Тестировать различные функции агрегации

**Главное:** Кластер работает, ON CLUSTER команды работают, шардирование работает! 🎉

Просто вставка данных требует дополнительной настройки прав на Windows.
