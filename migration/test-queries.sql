-- =====================================================
-- Тестовые запросы для проверки миграции и производительности
-- =====================================================

-- =====================================================
-- 1. ПРОВЕРКА РАСПРЕДЕЛЕНИЯ ДАННЫХ ПО ШАРДАМ
-- =====================================================

-- Распределение medical_services по шардам
SELECT
    _shard_num as shard,
    count() as total_rows,
    count(DISTINCT id) as unique_ids,
    formatReadableSize(sum(bytes_on_disk)) as size_on_disk,
    min(service_date) as min_date,
    max(service_date) as max_date
FROM outpatient.medical_services
GROUP BY _shard_num
ORDER BY _shard_num;

-- Распределение registers по шардам
SELECT
    _shard_num as shard,
    count() as total_rows,
    count(DISTINCT id) as unique_ids,
    count(DISTINCT medical_service_id) as unique_service_ids,
    formatReadableSize(sum(bytes_on_disk)) as size_on_disk
FROM outpatient.medical_service_registers
GROUP BY _shard_num
ORDER BY _shard_num;


-- =====================================================
-- 2. СРАВНЕНИЕ: ВСЕ ВЕРСИИ vs ТОЛЬКО АКТУАЛЬНЫЕ (FINAL)
-- =====================================================

-- medical_services: все версии
SELECT
    'all_versions' as type,
    count() as rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services;

-- medical_services: только актуальные (FINAL автоматически дедуплицирует)
SELECT
    'latest_versions_only' as type,
    count() as rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services_actual;

-- Проверка дубликатов по id
SELECT
    id,
    count() as version_count,
    max(version) as latest_version
FROM outpatient.medical_services
GROUP BY id
HAVING count() > 1
ORDER BY version_count DESC
LIMIT 10;


-- =====================================================
-- 3. JOIN ТЕСТ (Co-located на одном шарде)
-- =====================================================

-- Проверка эффективности JOIN (данные должны быть на одном шарде)
EXPLAIN
SELECT
    ms.id,
    ms.service_date,
    ms.person_id,
    ms.cost as service_cost,
    msr.payment_type_code,
    msr.cost as register_cost,
    msr.count as register_count
FROM outpatient.medical_services_actual ms
INNER JOIN outpatient.medical_service_registers_actual msr
    ON ms.id = msr.medical_service_id
WHERE ms.service_date >= '2024-01-01'
LIMIT 100;

-- Реальный JOIN запрос с агрегацией
SELECT
    ms.customer_org_id,
    count(DISTINCT ms.id) as service_count,
    sum(ms.cost) as total_service_cost,
    sum(msr.cost) as total_register_cost
FROM outpatient.medical_services_actual ms
INNER JOIN outpatient.medical_service_registers_actual msr
    ON ms.id = msr.medical_service_id
WHERE ms.service_date >= '2024-01-01'
GROUP BY ms.customer_org_id
ORDER BY total_service_cost DESC
LIMIT 20;


-- =====================================================
-- 4. ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ: ДО vs ПОСЛЕ МИГРАЦИИ
-- =====================================================

-- Запрос 1: Агрегация по датам (аналитика)
SELECT
    toYYYYMM(service_date) as month,
    count() as service_count,
    sum(cost) as total_cost,
    avg(cost) as avg_cost
FROM outpatient.medical_services_actual
WHERE service_date >= '2023-01-01'
GROUP BY month
ORDER BY month;

-- Запрос 2: Фильтрация по person_id (OLTP-стиль)
SELECT *
FROM outpatient.medical_services_actual
WHERE person_id = 'some-person-id-123'
  AND service_date >= '2023-01-01'
ORDER BY service_date DESC
LIMIT 100;

-- Запрос 3: Группировка по организациям
SELECT
    customer_org_id,
    performer_org_id,
    count() as service_count,
    sum(cost) as total_cost
FROM outpatient.medical_services_actual
WHERE service_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY customer_org_id, performer_org_id
HAVING service_count > 100
ORDER BY total_cost DESC
LIMIT 50;


-- =====================================================
-- 5. ПРОВЕРКА ДЕДУПЛИКАЦИИ (ReplacingMergeTree)
-- =====================================================

-- Статистика по версиям
SELECT
    max(version) as max_version,
    min(version) as min_version,
    count(DISTINCT version) as version_count
FROM outpatient.medical_services;

-- Найти записи, где ReplacingMergeTree еще не удалил старые версии
SELECT
    id,
    version,
    service_date,
    cost,
    _part as partition_part
FROM outpatient.medical_services
WHERE id IN (
    SELECT id
    FROM outpatient.medical_services
    GROUP BY id
    HAVING count() > 1
)
ORDER BY id, version;

-- Принудительная дедупликация конкретной партиции (если нужно)
-- OPTIMIZE TABLE outpatient.medical_services_local PARTITION '202401' FINAL;


-- =====================================================
-- 6. МОНИТОРИНГ РАЗМЕРА И ПАРТИЦИЙ
-- =====================================================

-- Размер таблиц по партициям
SELECT
    partition,
    sum(rows) as rows,
    formatReadableSize(sum(bytes_on_disk)) as size_on_disk,
    formatReadableSize(sum(data_compressed_bytes)) as compressed_size,
    count() as part_count
FROM system.parts
WHERE active
  AND database = 'outpatient'
  AND table LIKE '%medical_services%'
GROUP BY partition
ORDER BY partition DESC
LIMIT 20;

-- Размер индексов
SELECT
    table,
    name as index_name,
    type as index_type,
    formatReadableSize(sum(bytes_on_disk)) as index_size
FROM system.data_skipping_indices
WHERE database = 'outpatient'
GROUP BY table, name, type
ORDER BY table, index_size DESC;


-- =====================================================
-- 7. ВЕРИФИКАЦИЯ ЦЕЛОСТНОСТИ ДАННЫХ
-- =====================================================

-- Сравнение количества записей: исходник vs кластер
-- Выполните на исходном сервере (192.168.9.15):
SELECT
    'source' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids,
    max(version) as max_version
FROM outpatient.medical_services;

-- Выполните на новом кластере:
SELECT
    'target_all' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids,
    max(version) as max_version
FROM outpatient.medical_services;

SELECT
    'target_final' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids,
    max(version) as max_version
FROM outpatient.medical_services_actual;

-- Проверка контрольных сумм (опционально)
SELECT
    cityHash64(groupArray(id)) as id_checksum,
    sum(cost) as total_cost,
    count() as row_count
FROM (
    SELECT id, cost
    FROM outpatient.medical_services_actual
    ORDER BY id
    LIMIT 10000
);


-- =====================================================
-- 8. ПРИМЕРЫ ЗАПРОСОВ ДЛЯ ПРИЛОЖЕНИЙ
-- =====================================================

-- Пример 1: Получить все услуги пациента с регистрами
SELECT
    ms.id as service_id,
    ms.service_date,
    ms.service_code,
    ms.cost as service_cost,
    ms.person_id,
    msr.id as register_id,
    msr.payment_type_code,
    msr.cost as register_cost,
    msr.count as register_count
FROM outpatient.medical_services_actual ms
LEFT JOIN outpatient.medical_service_registers_actual msr
    ON ms.id = msr.medical_service_id
WHERE ms.person_id = '{{ person_id }}'
  AND ms.service_date >= '{{ start_date }}'
ORDER BY ms.service_date DESC, ms.id;

-- Пример 2: Аналитика по организациям за период
SELECT
    ms.customer_org_id,
    ms.performer_org_id,
    toYYYYMM(ms.service_date) as month,
    count(DISTINCT ms.id) as service_count,
    count(DISTINCT ms.person_id) as patient_count,
    sum(ms.cost) as total_service_cost,
    sum(msr.cost) as total_register_cost
FROM outpatient.medical_services_actual ms
LEFT JOIN outpatient.medical_service_registers_actual msr
    ON ms.id = msr.medical_service_id
WHERE ms.service_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
GROUP BY ms.customer_org_id, ms.performer_org_id, month
ORDER BY month DESC, total_service_cost DESC;

-- Пример 3: Поиск услуг по фильтрам
SELECT
    id,
    service_date,
    person_id,
    service_code,
    cost,
    customer_org_id,
    performer_org_id
FROM outpatient.medical_services_actual
WHERE 1=1
  AND (customer_org_id = '{{ org_id }}' OR performer_org_id = '{{ org_id }}')
  AND service_date BETWEEN '{{ start_date }}' AND '{{ end_date }}'
  AND (service_code = '{{ service_code }}' OR '{{ service_code }}' = '')
ORDER BY service_date DESC
LIMIT 1000;


-- =====================================================
-- 9. ОЧИСТКА СТАРЫХ ДАННЫХ (После миграции)
-- =====================================================

-- Удалить партиции старше 3 лет (пример)
-- ALTER TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster'
--     DROP PARTITION '202001';

-- Удалить все данные конкретной партиции
-- ALTER TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster'
--     DROP PARTITION '202012';


-- =====================================================
-- 10. ПОЛЕЗНЫЕ СИСТЕМНЫЕ ЗАПРОСЫ
-- =====================================================

-- Активные запросы на кластере
SELECT
    query_id,
    user,
    address,
    elapsed,
    formatReadableSize(memory_usage) as memory,
    query
FROM system.processes
WHERE query NOT LIKE '%system.processes%';

-- Самые медленные запросы за последний час
SELECT
    type,
    event_time,
    query_duration_ms,
    formatReadableSize(memory_usage) as memory,
    substring(query, 1, 100) as query_preview
FROM system.query_log
WHERE event_time >= now() - INTERVAL 1 HOUR
  AND type = 'QueryFinish'
ORDER BY query_duration_ms DESC
LIMIT 20;

-- Размер кластера
SELECT
    sum(bytes_on_disk) / (1024 * 1024 * 1024) as size_gb,
    sum(rows) as total_rows
FROM system.parts
WHERE active
  AND database = 'outpatient';
