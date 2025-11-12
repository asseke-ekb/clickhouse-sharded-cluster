# Руководство по миграции Medical Services в шардированный ClickHouse кластер

## 📋 Обзор миграции

### Что мигрируем:
- **Исходник:** ClickHouse на 192.168.9.15 (монолитный сервер)
- **Целевой кластер:** 4 шарда без репликации
- **Таблицы:**
  - `outpatient.medical_services`
  - `outpatient.medical_service_registers`

### Ключевые изменения:
1. **MergeTree → ReplacingMergeTree** - автоматическая дедупликация версий
2. **Монолит → Шардирование** - распределение по 4 шардам
3. **Co-located JOIN** - данные связанных таблиц на одном шарде

---

## 🎯 Цели миграции

### Проблемы, которые решаем:

1. ❌ **Медленные запросы** - все версии хранятся, выборка последней версии долгая
2. ❌ **Отсутствие масштабирования** - один сервер, нельзя добавить мощности
3. ❌ **Ручная дедупликация** - нужно вручную фильтровать по `max(version)`

### Что получаем после миграции:

1. ✅ **Автоматическая дедупликация** - ReplacingMergeTree удаляет старые версии
2. ✅ **Горизонтальное масштабирование** - 4 шарда, можно добавлять новые
3. ✅ **Быстрые запросы** - данные распределены, запросы параллельные
4. ✅ **Co-located JOIN** - связанные данные на одном шарде (быстрый JOIN)

---

## 🔧 Архитектура решения

### Стратегия шардирования:

```
medical_services:
├─ Шардирование: sipHash64(id)
├─ ORDER BY: (id, service_date, version)
└─ Engine: ReplacingMergeTree(version)

medical_service_registers:
├─ Шардирование: sipHash64(medical_service_id)
├─ ORDER BY: (medical_service_id, id, version)
└─ Engine: ReplacingMergeTree(version)
```

**Почему такое шардирование?**
- `medical_services.id` = `medical_service_registers.medical_service_id`
- При JOIN связанные записи окажутся на одном шарде (co-located JOIN)
- Это значительно ускоряет запросы с JOIN

### Схема распределения:

```
┌─────────────────────────────────────────┐
│   ZooKeeper (координация DDL)          │
└─────────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┬─────────┐
    │             │             │         │
┌───▼───┐     ┌───▼───┐     ┌──▼───┐  ┌──▼───┐
│Shard-1│     │Shard-2│     │Shard-3│ │Shard-4│
│ 25%   │     │ 25%   │     │ 25%   │ │ 25%   │
│данных │     │данных │     │данных │ │данных │
└───────┘     └───────┘     └───────┘ └───────┘
```

---

## 📝 Пошаговая инструкция

### Шаг 1: Подготовка кластера (если еще не настроен)

#### 1.1. Обновить конфигурацию для 4 шардов

Если у вас сейчас 3 шарда, нужно добавить 4-й:

**Отредактируйте `shard-*/config/clickhouse/config.xml`:**

```xml
<remote_servers>
    <dwh_sharded_cluster>
        <shard>
            <internal_replication>false</internal_replication>
            <replica><host>clickhouse-shard-01</host><port>9000</port></replica>
        </shard>
        <shard>
            <internal_replication>false</internal_replication>
            <replica><host>clickhouse-shard-02</host><port>9000</port></replica>
        </shard>
        <shard>
            <internal_replication>false</internal_replication>
            <replica><host>clickhouse-shard-03</host><port>9000</port></replica>
        </shard>
        <shard>
            <internal_replication>false</internal_replication>
            <replica><host>clickhouse-shard-04</host><port>9000</port></replica>
        </shard>
    </dwh_sharded_cluster>
</remote_servers>
```

#### 1.2. Создать shard-4 директорию (если нужно)

```bash
cd clickhouse_shard
cp -r shard-3 shard-4

# Отредактировать docker-compose.yml для shard-4
# Изменить порты: 8126 (HTTP), 9003 (TCP), 9012 (interserver)
```

#### 1.3. Запустить 4-й шард

```bash
docker-compose -f docker-compose-full.yml up -d
# или если отдельные compose файлы:
cd shard-4 && docker-compose up -d
```

---

### Шаг 2: Создание схемы на кластере

#### 2.1. Выполнить SQL скрипт

Подключитесь к любому узлу кластера (например, shard-1):

```bash
docker exec -it clickhouse-shard-01 clickhouse-client --user admin --password admin123
```

Выполните скрипт:

```bash
clickhouse-client --user admin --password admin123 --multiquery < migration/medical-services-schema.sql
```

#### 2.2. Проверить создание таблиц

```sql
-- Проверить, что таблицы созданы на всех шардах
SELECT
    shard_num,
    database,
    table,
    engine
FROM cluster('dwh_sharded_cluster', system.tables)
WHERE database = 'outpatient'
  AND table LIKE '%medical_%'
ORDER BY shard_num, table;
```

Ожидаемый результат:
- 4 шарда × 2 локальные таблицы (_local) = 8 строк
- 2 distributed таблицы (без _local)
- 2 VIEW таблицы (_actual)

---

### Шаг 3: Настройка Airflow

#### 3.1. Установить зависимости

```bash
pip install apache-airflow-providers-common-sql
pip install clickhouse-connect
```

#### 3.2. Создать Airflow Connections

**В Airflow UI (Admin → Connections):**

**Connection 1: Исходный ClickHouse**
- Connection Id: `clickhouse_source`
- Connection Type: `ClickHouse`
- Host: `192.168.9.15`
- Port: `9000` (native) или `8123` (http)
- Login: `default`
- Password: (ваш пароль)

**Connection 2: Целевой кластер**
- Connection Id: `clickhouse_cluster`
- Connection Type: `ClickHouse`
- Host: (IP первого узла кластера, например `192.168.9.110`)
- Port: `8123`
- Login: `admin`
- Password: `admin123`

#### 3.3. Скопировать DAG файл

```bash
cp migration/airflow_migration_dag.py $AIRFLOW_HOME/dags/
```

#### 3.4. Проверить DAG в Airflow UI

Перейдите в Airflow UI и убедитесь, что DAG появился:
- DAG ID: `medical_services_migration_to_cluster`
- Status: Enabled

---

### Шаг 4: Запуск миграции

#### 4.1. Ручной запуск через Airflow UI

1. Откройте DAG в Airflow UI
2. Нажмите кнопку **"Trigger DAG"**
3. Подтвердите запуск

#### 4.2. Мониторинг прогресса

- **Graph View** - визуальное представление прогресса
- **Logs** - детальные логи каждой задачи
- Миграция идет батчами по месяцам

**Ожидаемое время выполнения:**
- ~2-4 часа для 50M записей
- Зависит от размера данных и скорости сети

#### 4.3. Мониторинг в ClickHouse

```sql
-- Проверить текущий прогресс
SELECT
    _shard_num as shard,
    count() as rows_migrated,
    formatReadableSize(sum(bytes_on_disk)) as size
FROM outpatient.medical_services
GROUP BY _shard_num;

-- Проверить активные вставки
SELECT
    query,
    elapsed,
    formatReadableSize(memory_usage) as memory
FROM system.processes
WHERE query LIKE '%INSERT INTO outpatient%';
```

---

### Шаг 5: Верификация данных

#### 5.1. Сравнить количество записей

**На исходном сервере (192.168.9.15):**

```sql
SELECT
    'source' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services;
```

**На новом кластере:**

```sql
-- Все версии (включая дубликаты)
SELECT
    'target_all_versions' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services;

-- Только актуальные версии (FINAL)
SELECT
    'target_latest_only' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services_actual;
```

#### 5.2. Проверить распределение по шардам

```sql
SELECT
    _shard_num as shard,
    count() as rows,
    formatReadableSize(sum(bytes_on_disk)) as size,
    round(count() * 100.0 / (SELECT count() FROM outpatient.medical_services), 2) as percent
FROM outpatient.medical_services
GROUP BY _shard_num
ORDER BY _shard_num;
```

**Ожидаемый результат:** Примерно 25% данных на каждом шарде (±5%)

#### 5.3. Проверить JOIN

```sql
-- Тестовый JOIN
SELECT
    count(*) as join_rows,
    count(DISTINCT ms.id) as service_count,
    count(DISTINCT msr.id) as register_count
FROM outpatient.medical_services_actual ms
INNER JOIN outpatient.medical_service_registers_actual msr
    ON ms.id = msr.medical_service_id
WHERE ms.service_date >= '2024-01-01';
```

---

### Шаг 6: Оптимизация (после миграции)

#### 6.1. Принудительная дедупликация

ReplacingMergeTree дедуплицирует автоматически при слиянии партиций, но можно запустить вручную:

```sql
-- Для всех партиций на всех шардах
OPTIMIZE TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster' FINAL;
OPTIMIZE TABLE outpatient.medical_service_registers_local ON CLUSTER 'dwh_sharded_cluster' FINAL;
```

**⚠️ Внимание:** OPTIMIZE TABLE - ресурсоемкая операция, запускайте в нерабочее время!

#### 6.2. Проверка после OPTIMIZE

```sql
-- Проверить, что дубликатов больше нет
SELECT
    id,
    count() as version_count
FROM outpatient.medical_services
GROUP BY id
HAVING count() > 1
LIMIT 10;

-- Должно вернуть 0 строк
```

---

### Шаг 7: Переключение приложений

#### 7.1. Обновить connection strings в приложениях

**Старое подключение:**
```
Host: 192.168.9.15
Port: 8123
```

**Новое подключение (любой узел кластера):**
```
Host: 192.168.9.110  (или 111, 112, 113)
Port: 8123
Database: outpatient
```

#### 7.2. Изменить SQL запросы в приложениях

**Было (старый способ получения последней версии):**
```sql
SELECT *
FROM outpatient.medical_services
WHERE (id, version) IN (
    SELECT id, MAX(version)
    FROM outpatient.medical_services
    GROUP BY id
)
```

**Стало (с ReplacingMergeTree):**
```sql
-- Вариант 1: С FINAL (гарантированно актуальные данные)
SELECT * FROM outpatient.medical_services_actual;

-- Вариант 2: Без FINAL (быстрее, но могут быть дубликаты до OPTIMIZE)
SELECT * FROM outpatient.medical_services;
```

#### 7.3. Рекомендации по запросам

1. **Для аналитики / отчетов:** Используйте VIEW с `_actual` (FINAL)
2. **Для OLTP / быстрых запросов:** Используйте таблицу без FINAL
3. **JOIN запросы:** Всегда используйте `_actual` VIEW для корректности

---

## 🔍 Тестирование производительности

### Сравнение: До vs После

Выполните тестовые запросы из файла `test-queries.sql`:

```bash
clickhouse-client --user admin --password admin123 < migration/test-queries.sql > results.txt
```

**Метрики для сравнения:**
- Время выполнения запросов (elapsed)
- Использование памяти (memory_usage)
- Количество прочитанных строк (read_rows)

---

## 🚨 Troubleshooting

### Проблема 1: Миграция застряла

**Симптомы:** Airflow DAG висит на одной задаче долго

**Решение:**
```sql
-- Проверить активные запросы
SELECT query_id, elapsed, query
FROM system.processes
WHERE query LIKE '%INSERT INTO outpatient%';

-- Убить зависший запрос (если нужно)
KILL QUERY WHERE query_id = 'xxx';
```

### Проблема 2: Неравномерное распределение по шардам

**Симптомы:** Один шард имеет 50% данных, остальные по 15%

**Причина:** Неравномерное распределение ключа шардирования

**Решение:**
- Проверьте распределение `sipHash64(id)` в исходных данных
- Возможно, стоит использовать другой ключ (`rand()` для случайного распределения)

### Проблема 3: JOIN работает медленно

**Симптомы:** JOIN запросы выполняются 10+ секунд

**Причина:** Данные не на одном шарде (не co-located)

**Решение:**
- Проверьте, что `medical_services` шардируется по `id`
- Проверьте, что `medical_service_registers` шардируется по `medical_service_id`
- Убедитесь, что в JOIN условие: `ms.id = msr.medical_service_id`

### Проблема 4: Дубликаты не удаляются

**Симптомы:** После миграции видны старые версии записей

**Причина:** ReplacingMergeTree дедуплицирует только при слиянии партиций

**Решение:**
```sql
-- Принудительное слияние
OPTIMIZE TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster' FINAL;

-- Или используйте VIEW с FINAL
SELECT * FROM outpatient.medical_services_actual;
```

---

## 📊 Мониторинг после миграции

### Ежедневные проверки

```sql
-- 1. Размер данных на шардах
SELECT
    _shard_num,
    count() as rows,
    formatReadableSize(sum(bytes_on_disk)) as size
FROM outpatient.medical_services
GROUP BY _shard_num;

-- 2. Количество дубликатов (должно быть 0 после OPTIMIZE)
SELECT count(*) as duplicate_count
FROM (
    SELECT id
    FROM outpatient.medical_services
    GROUP BY id
    HAVING count() > 1
);

-- 3. Самые медленные запросы за последний час
SELECT
    query_duration_ms,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 100) as query_preview
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 HOUR
  AND type = 'QueryFinish'
ORDER BY query_duration_ms DESC
LIMIT 10;
```

---

## 🗑️ Откат миграции (Rollback)

Если что-то пошло не так, можно откатиться:

```sql
-- 1. Удалить таблицы на кластере
DROP DATABASE outpatient ON CLUSTER 'dwh_sharded_cluster';

-- 2. Вернуться к старому серверу 192.168.9.15
-- (исходные данные не трогали, они остались)

-- 3. Обновить connection strings в приложениях
```

---

## ✅ Checklist после успешной миграции

- [ ] Количество записей совпадает (source vs target)
- [ ] Распределение по шардам равномерное (~25% на каждом)
- [ ] JOIN запросы работают корректно
- [ ] OPTIMIZE TABLE выполнен, дубликатов нет
- [ ] Приложения переключены на новый кластер
- [ ] Производительность запросов улучшилась
- [ ] Мониторинг настроен (Grafana/Prometheus)
- [ ] Backup кластера настроен

---

## 📚 Дополнительные материалы

- [medical-services-schema.sql](medical-services-schema.sql) - SQL схема для кластера
- [airflow_migration_dag.py](airflow_migration_dag.py) - Airflow DAG для миграции
- [test-queries.sql](test-queries.sql) - Тестовые запросы и проверки
- [ClickHouse ReplacingMergeTree](https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replacingmergetree)
- [ClickHouse Distributed Tables](https://clickhouse.com/docs/en/engines/table-engines/special/distributed)

---

**Автор:** Claude Code
**Дата:** 2025-01-12
**Версия:** 1.0
