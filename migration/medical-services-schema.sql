-- =====================================================
-- Migration Schema: medical_services to 4-shard cluster
-- Engine: ReplacingMergeTree (автоудаление старых версий)
-- Sharding: по id для оптимизации JOIN
-- =====================================================

-- 1. Создать базу данных на всех шардах
CREATE DATABASE IF NOT EXISTS outpatient ON CLUSTER 'dwh_sharded_cluster';

-- =====================================================
-- Таблица: medical_services
-- =====================================================

-- 1.1. Локальная таблица на каждом шарде (ReplacingMergeTree)
CREATE TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster'
(
    `id_clickhouse` String DEFAULT toString(generateUUIDv4()),
    `insert_date_clickhouse` DateTime DEFAULT now(),
    `version` UInt64,
    `id` String,
    `service_date` Date,
    `eps_id` Nullable(Int64),
    `customer_org_id` String,
    `performer_org_id` String,
    `customer_dep_id` String,
    `performer_dep_id` String,
    `customer_emp_id` String,
    `performer_emp_id` String,
    `original_service_id` Nullable(String),
    `person_id` String,
    `finance_source_code` Nullable(String),
    `visit_kind_code` Nullable(String),
    `cost` Nullable(Decimal(18, 2)),
    `count` Nullable(Decimal(18, 2)),
    `is_main` Nullable(UInt8),
    `leasing` Nullable(String),
    `icd10_id` Nullable(String),
    `service_cds_kind` Nullable(String),
    `payment_type_code` Nullable(String),
    `confirmation_date` Nullable(Date),
    `result_id` Nullable(String),
    `service_code` Nullable(String),
    `removal_date` Nullable(Date),
    `place_code` Nullable(String),
    `active_visit_type_code` Nullable(String),
    `screening_group_code` Nullable(String),
    `parent_id` String,
    `diagnosis_type` Nullable(String),
    `datasource` Nullable(String),
    `fsms_finance_source_code` Nullable(String),
    `refferal_id` Nullable(String),
    `created_date` Nullable(Date),
    `updated_date` Nullable(Date),
    `treatment_reason_id` Nullable(String),
    `person_age` Nullable(Int32),
    `medical_care_sub_type_code` Nullable(String),
    `register_id` Nullable(String),

    INDEX id_index id TYPE minmax GRANULARITY 4,
    INDEX service_date_index service_date TYPE minmax GRANULARITY 4,
    INDEX person_id_index person_id TYPE minmax GRANULARITY 4
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(service_date)
ORDER BY (id, service_date, version)
SETTINGS index_granularity = 8192;

-- 1.2. Distributed таблица для записи (автоматическое распределение по шардам)
CREATE TABLE outpatient.medical_services ON CLUSTER 'dwh_sharded_cluster'
AS outpatient.medical_services_local
ENGINE = Distributed('dwh_sharded_cluster', 'outpatient', 'medical_services_local', sipHash64(id));

-- 1.3. VIEW для чтения ТОЛЬКО актуальных версий (FINAL убирает дубликаты)
CREATE VIEW outpatient.medical_services_actual ON CLUSTER 'dwh_sharded_cluster'
AS SELECT * FROM outpatient.medical_services FINAL;


-- =====================================================
-- Таблица: medical_service_registers
-- =====================================================

-- 2.1. Локальная таблица на каждом шарде (ReplacingMergeTree)
CREATE TABLE outpatient.medical_service_registers_local ON CLUSTER 'dwh_sharded_cluster'
(
    `id_clickhouse` String DEFAULT toString(generateUUIDv4()),
    `insert_date_clickhouse` DateTime DEFAULT now(),
    `version` UInt64,
    `id` String,
    `medical_service_id` String,
    `payment_type_code` String,
    `customer_org_id` String,
    `performer_org_id` String,
    `customer_dep_id` Nullable(String),
    `performer_dep_id` Nullable(String),
    `customer_emp_id` Nullable(String),
    `performer_emp_id` Nullable(String),
    `count` Decimal(18, 2),
    `cost` Decimal(18, 2),
    `income_date` Nullable(DateTime),
    `created_date` Nullable(DateTime),
    `updated_date` Nullable(DateTime),
    `service_date` Nullable(DateTime),
    `register_id` Nullable(String),
    `service_cds_kind` Nullable(String),
    `date_verified` Nullable(DateTime),

    INDEX id_index id TYPE minmax GRANULARITY 4,
    INDEX medical_service_id_index medical_service_id TYPE minmax GRANULARITY 4
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(insert_date_clickhouse)
ORDER BY (medical_service_id, id, version)
SETTINGS index_granularity = 8192;

-- 2.2. Distributed таблица (шардирование по medical_service_id для co-located JOIN)
CREATE TABLE outpatient.medical_service_registers ON CLUSTER 'dwh_sharded_cluster'
AS outpatient.medical_service_registers_local
ENGINE = Distributed('dwh_sharded_cluster', 'outpatient', 'medical_service_registers_local', sipHash64(medical_service_id));

-- 2.3. VIEW для чтения ТОЛЬКО актуальных версий
CREATE VIEW outpatient.medical_service_registers_actual ON CLUSTER 'dwh_sharded_cluster'
AS SELECT * FROM outpatient.medical_service_registers FINAL;


-- =====================================================
-- ВАЖНЫЕ ЗАМЕЧАНИЯ
-- =====================================================

/*
1. ReplacingMergeTree(version):
   - Автоматически удаляет строки с одинаковым ORDER BY ключом
   - Оставляет только строку с максимальным значением version
   - Дедупликация происходит при слиянии партиций (OPTIMIZE TABLE)

2. Шардирование:
   - medical_services: sipHash64(id)
   - medical_service_registers: sipHash64(medical_service_id)
   - ✅ Это обеспечивает co-located JOIN - связанные данные на одном шарде

3. ORDER BY ключи:
   - medical_services: (id, service_date, version)
   - medical_service_registers: (medical_service_id, id, version)
   - ⚠️ version должен быть в конце для корректной работы ReplacingMergeTree

4. FINAL:
   - Используйте VIEW с FINAL для гарантированно актуальных данных
   - FINAL работает медленнее, но дает точный результат
   - Для аналитики без FINAL - данные будут дедуплицироваться постепенно

5. Партиционирование:
   - medical_services: по service_date (для эффективной очистки старых данных)
   - medical_service_registers: по insert_date_clickhouse

6. Миграция:
   - Переносите данные батчами по 100k-1M записей
   - Используйте INSERT INTO ... SELECT с фильтрацией по датам
   - После миграции выполните OPTIMIZE TABLE для принудительной дедупликации
*/

-- =====================================================
-- Проверка после создания
-- =====================================================

-- Проверить, что таблицы созданы на всех шардах
SELECT
    cluster,
    shard_num,
    database,
    table,
    engine
FROM system.tables
WHERE database = 'outpatient'
  AND table LIKE '%medical_%';

-- Проверить кластер
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';
