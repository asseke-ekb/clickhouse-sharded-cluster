# Миграция Medical Services через KNIME

Руководство по миграции таблиц `medical_services` и `medical_service_registers` из монолитного ClickHouse в шардированный кластер с использованием KNIME Analytics Platform.

## 🎯 Преимущества KNIME для миграции

1. ✅ **Визуальный workflow** - видно весь процесс миграции
2. ✅ **Батчинг из коробки** - встроенная поддержка порционной обработки
3. ✅ **Мониторинг в реальном времени** - progress bar, логи
4. ✅ **Легко отлаживать** - можно проверить данные на любом этапе
5. ✅ **Переиспользование** - workflow можно запускать многократно
6. ✅ **Планировщик задач** - KNIME Server для автоматизации

---

## 📋 Требования

### Установка KNIME

1. **KNIME Analytics Platform** (бесплатная версия достаточно)
   - Скачать: https://www.knime.com/downloads
   - Версия: 5.2.0 или новее

2. **Необходимые расширения:**
   - KNIME Database Extension (встроено)
   - KNIME Big Data Extensions (опционально)

### ClickHouse JDBC Driver

Скачайте JDBC драйвер:
```
https://github.com/ClickHouse/clickhouse-jdbc/releases
```

Файл: `clickhouse-jdbc-x.x.x-all.jar`

---

## 🔧 Настройка подключений в KNIME

### 1. Добавить ClickHouse JDBC Driver

1. Откройте KNIME
2. **File → Preferences → KNIME → Databases**
3. Нажмите **Add**
4. Укажите путь к `clickhouse-jdbc-x.x.x-all.jar`

### 2. Создать Database Connections

#### Connection 1: Исходный ClickHouse (192.168.9.15)

**В KNIME Workflow добавьте узел: Database Connector**

Параметры:
- **Database Type:** Generic JDBC
- **Driver:** `com.clickhouse.jdbc.ClickHouseDriver`
- **JDBC URL:** `jdbc:clickhouse://192.168.9.15:8123/outpatient`
- **Authentication:**
  - Username: `default`
  - Password: (ваш пароль)
- **Advanced:**
  - `socket_timeout=600000` (10 минут таймаут)

#### Connection 2: Целевой кластер (любой узел)

**В KNIME Workflow добавьте узел: Database Connector**

Параметры:
- **Database Type:** Generic JDBC
- **Driver:** `com.clickhouse.jdbc.ClickHouseDriver`
- **JDBC URL:** `jdbc:clickhouse://192.168.9.110:8123/outpatient`
  - (или IP любого узла вашего кластера)
- **Authentication:**
  - Username: `admin`
  - Password: `admin123`

---

## 🏗️ KNIME Workflow: Структура

### Общая схема workflow

```
┌─────────────────────────────────────────────────────────┐
│  МЕТАДАННЫЕ И ПОДГОТОВКА                                │
├─────────────────────────────────────────────────────────┤
│  1. Database Connector (Source)                         │
│  2. Database Connector (Target)                         │
│  3. Table Creator (создание схемы на кластере)          │
└─────────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────┐
│  МИГРАЦИЯ medical_services                              │
├─────────────────────────────────────────────────────────┤
│  4. DB Table Selector (список месяцев для батчинга)     │
│  5. Group Loop Start (по месяцам)                       │
│  6. DB Query Reader (читать батч из источника)          │
│  7. DB Writer (писать в кластер)                        │
│  8. Variable Loop End                                   │
└─────────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────┐
│  МИГРАЦИЯ medical_service_registers                     │
├─────────────────────────────────────────────────────────┤
│  9. Group Loop Start (по месяцам)                       │
│  10. DB Query Reader (читать батч из источника)         │
│  11. DB Writer (писать в кластер)                       │
│  12. Variable Loop End                                  │
└─────────────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────────────┐
│  ОПТИМИЗАЦИЯ И ПРОВЕРКА                                 │
├─────────────────────────────────────────────────────────┤
│  13. DB SQL Executor (OPTIMIZE TABLE)                   │
│  14. DB Query Reader (проверка количества записей)      │
│  15. DB Query Reader (распределение по шардам)          │
└─────────────────────────────────────────────────────────┘
```

---

## 📝 Пошаговая инструкция создания Workflow

### Шаг 1: Создание схемы на кластере

#### Узел: DB SQL Executor

**Настройки:**
- Connection: Target Cluster
- SQL Statement:

```sql
-- Создать базу данных
CREATE DATABASE IF NOT EXISTS outpatient ON CLUSTER 'dwh_sharded_cluster';

-- Создать таблицу medical_services_local
CREATE TABLE IF NOT EXISTS outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster'
(
    id_clickhouse String DEFAULT toString(generateUUIDv4()),
    insert_date_clickhouse DateTime DEFAULT now(),
    version UInt64,
    id String,
    service_date Date,
    eps_id Nullable(Int64),
    customer_org_id String,
    performer_org_id String,
    customer_dep_id String,
    performer_dep_id String,
    customer_emp_id String,
    performer_emp_id String,
    original_service_id Nullable(String),
    person_id String,
    finance_source_code Nullable(String),
    visit_kind_code Nullable(String),
    cost Nullable(Decimal(18, 2)),
    count Nullable(Decimal(18, 2)),
    is_main Nullable(UInt8),
    leasing Nullable(String),
    icd10_id Nullable(String),
    service_cds_kind Nullable(String),
    payment_type_code Nullable(String),
    confirmation_date Nullable(Date),
    result_id Nullable(String),
    service_code Nullable(String),
    removal_date Nullable(Date),
    place_code Nullable(String),
    active_visit_type_code Nullable(String),
    screening_group_code Nullable(String),
    parent_id String,
    diagnosis_type Nullable(String),
    datasource Nullable(String),
    fsms_finance_source_code Nullable(String),
    refferal_id Nullable(String),
    created_date Nullable(Date),
    updated_date Nullable(Date),
    treatment_reason_id Nullable(String),
    person_age Nullable(Int32),
    medical_care_sub_type_code Nullable(String),
    register_id Nullable(String),
    INDEX id_index id TYPE minmax GRANULARITY 4
)
ENGINE = ReplacingMergeTree(version)
PARTITION BY toYYYYMM(service_date)
ORDER BY (id, service_date, version)
SETTINGS index_granularity = 8192;

-- Создать distributed таблицу
CREATE TABLE IF NOT EXISTS outpatient.medical_services ON CLUSTER 'dwh_sharded_cluster'
AS outpatient.medical_services_local
ENGINE = Distributed('dwh_sharded_cluster', 'outpatient', 'medical_services_local', sipHash64(id));

-- Создать VIEW для актуальных версий
CREATE VIEW IF NOT EXISTS outpatient.medical_services_actual ON CLUSTER 'dwh_sharded_cluster'
AS SELECT * FROM outpatient.medical_services FINAL;
```

**Аналогично для `medical_service_registers`** (см. файл `medical-services-schema.sql`)

---

### Шаг 2: Генерация списка месяцев для батчинга

#### Узел: Table Creator

**Настройки:**
- Создайте таблицу с колонками:
  - `year_month` (String): "2020-01", "2020-02", ..., "2025-01"
  - `start_date` (String): "2020-01-01", "2020-02-01", ...
  - `end_date` (String): "2020-02-01", "2020-03-01", ...

Можно использовать **Python Script** или **Java Snippet** для генерации:

```python
# Python Script (2:1)
import pandas as pd
from datetime import datetime, timedelta
from dateutil.relativedelta import relativedelta

start = datetime(2020, 1, 1)
end = datetime(2025, 1, 1)

months = []
current = start
while current < end:
    next_month = current + relativedelta(months=1)
    months.append({
        'year_month': current.strftime('%Y-%m'),
        'start_date': current.strftime('%Y-%m-%d'),
        'end_date': next_month.strftime('%Y-%m-%d')
    })
    current = next_month

output_table = pd.DataFrame(months)
```

---

### Шаг 3: Миграция medical_services (Loop)

#### Узел 1: Group Loop Start

**Настройки:**
- Iterate over: Rows
- Loop Variable: `current_month`

#### Узел 2: DB Query Reader (внутри Loop)

**Настройки:**
- Connection: Source DB
- SQL Query (с использованием Flow Variables):

```sql
SELECT
    id_clickhouse,
    insert_date_clickhouse,
    version,
    id,
    service_date,
    eps_id,
    customer_org_id,
    performer_org_id,
    customer_dep_id,
    performer_dep_id,
    customer_emp_id,
    performer_emp_id,
    original_service_id,
    person_id,
    finance_source_code,
    visit_kind_code,
    cost,
    count,
    is_main,
    leasing,
    icd10_id,
    service_cds_kind,
    payment_type_code,
    confirmation_date,
    result_id,
    service_code,
    removal_date,
    place_code,
    active_visit_type_code,
    screening_group_code,
    parent_id,
    diagnosis_type,
    datasource,
    fsms_finance_source_code,
    refferal_id,
    created_date,
    updated_date,
    treatment_reason_id,
    person_age,
    medical_care_sub_type_code,
    register_id
FROM outpatient.medical_services
WHERE service_date >= toDate('${current_month_start_date}')
  AND service_date < toDate('${current_month_end_date}')
```

**Использование Flow Variables:**
1. На узле **DB Query Reader** → Configure → Flow Variables
2. Добавить переменные:
   - `current_month_start_date` → из `start_date`
   - `current_month_end_date` → из `end_date`

#### Узел 3: DB Writer (внутри Loop)

**Настройки:**
- Connection: Target Cluster
- Table: `outpatient.medical_services`
- Write mode: **Append** (добавлять данные)
- Batch size: 10000 (записей за раз)

#### Узел 4: Variable Loop End

**Настройки:**
- Collect rows: No (не нужно собирать данные, только считать итерации)

---

### Шаг 4: Миграция medical_service_registers

**Аналогично Шагу 3**, но с другой таблицей:

```sql
SELECT
    id_clickhouse,
    insert_date_clickhouse,
    version,
    id,
    medical_service_id,
    payment_type_code,
    customer_org_id,
    performer_org_id,
    customer_dep_id,
    performer_dep_id,
    customer_emp_id,
    performer_emp_id,
    count,
    cost,
    income_date,
    created_date,
    updated_date,
    service_date,
    register_id,
    service_cds_kind,
    date_verified
FROM outpatient.medical_service_registers
WHERE insert_date_clickhouse >= toDateTime('${current_month_start_date}')
  AND insert_date_clickhouse < toDateTime('${current_month_end_date}')
```

---

### Шаг 5: Оптимизация после миграции

#### Узел: DB SQL Executor

**Настройки:**
- Connection: Target Cluster
- SQL Statement:

```sql
-- Принудительная дедупликация на всех шардах
OPTIMIZE TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster' FINAL;
OPTIMIZE TABLE outpatient.medical_service_registers_local ON CLUSTER 'dwh_sharded_cluster' FINAL;
```

⚠️ **Внимание:** OPTIMIZE TABLE может занять несколько часов для больших таблиц!

---

### Шаг 6: Верификация данных

#### Узел 1: DB Query Reader (проверка количества)

```sql
SELECT
    'source' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids
FROM remote('192.168.9.15:9000', 'outpatient.medical_services', 'default', '')

UNION ALL

SELECT
    'target_all' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services

UNION ALL

SELECT
    'target_final' as location,
    count() as total_rows,
    count(DISTINCT id) as unique_ids
FROM outpatient.medical_services_actual
```

#### Узел 2: DB Query Reader (распределение по шардам)

```sql
SELECT
    _shard_num as shard,
    count() as rows,
    round(count() * 100.0 / (SELECT count() FROM outpatient.medical_services), 2) as percent,
    formatReadableSize(sum(bytes_on_disk)) as size_on_disk
FROM outpatient.medical_services
GROUP BY _shard_num
ORDER BY _shard_num
```

#### Узел 3: Table View

Для визуализации результатов проверки.

---

## 🚀 Оптимизация производительности KNIME

### 1. Увеличить размер батча

В узле **DB Writer**:
- Batch size: `50000` (вместо 10000)
- Это уменьшит количество round-trips к БД

### 2. Параллельные потоки (если есть KNIME Server)

Можно запустить несколько workflow параллельно:
- Workflow 1: Миграция 2020-2021
- Workflow 2: Миграция 2022-2023
- Workflow 3: Миграция 2024-2025

### 3. Использовать DB Loader вместо DB Writer

**DB Loader** (если поддерживается ClickHouse):
- Быстрее, чем DB Writer
- Использует нативный протокол загрузки

### 4. Увеличить память KNIME

В `knime.ini`:
```
-Xmx8g
```

---

## 📊 Мониторинг прогресса

### В KNIME UI:

1. **Progress Bar** - показывает прогресс текущего узла
2. **Console View** - логи выполнения
3. **Node Monitor** - статистика по времени и памяти

### Добавить логирование

#### Узел: Java Snippet (внутри Loop)

```java
// Логирование прогресса
String month = getVariable("current_month", "string");
int rowCount = inData[0].getRowCount();
System.out.println("Migrating month: " + month + ", rows: " + rowCount);
```

---

## 🎯 Пример готового Workflow (псевдокод)

```
[Database Connector: Source] ────┐
                                 │
[Database Connector: Target] ────┼─→ [DB SQL Executor: Create Schema]
                                 │
                                 │
[Table Creator: Month List] ─────┼─→ [Group Loop Start]
                                     ├─→ [DB Query Reader: Read Batch] (Source)
                                     ├─→ [DB Writer: Write to Cluster] (Target)
                                     └─→ [Variable Loop End]
                                         │
                                         ↓
                                     [DB SQL Executor: OPTIMIZE TABLE]
                                         │
                                         ↓
                                     [DB Query Reader: Verify Count]
                                         │
                                         ↓
                                     [DB Query Reader: Shard Distribution]
                                         │
                                         ↓
                                     [Table View: Results]
```

---

## 💾 Экспорт Workflow

После создания workflow сохраните его:

1. **File → Export KNIME Workflow**
2. Сохранить как: `medical_services_migration.knwf`
3. Можно импортировать на другой машине или KNIME Server

---

## 🐛 Troubleshooting

### Ошибка: "Connection timeout"

**Решение:**
```
jdbc:clickhouse://192.168.9.15:8123/outpatient?socket_timeout=600000&connect_timeout=60000
```

### Ошибка: "Out of memory"

**Решение:**
1. Уменьшить размер батча (Batch size: 10000 → 5000)
2. Увеличить память KNIME в `knime.ini`

### Ошибка: "Table already exists"

**Решение:**
- Используйте `CREATE TABLE IF NOT EXISTS`
- Или удалите таблицу перед запуском: `DROP TABLE IF EXISTS`

### Данные мигрируются медленно

**Решение:**
1. Увеличить Batch size до 50000
2. Использовать параллельные workflow
3. Проверить сетевую скорость между серверами

---

## ✅ Checklist перед запуском

- [ ] KNIME Analytics Platform установлен
- [ ] ClickHouse JDBC драйвер добавлен
- [ ] Database Connectors настроены (source + target)
- [ ] Схема создана на кластере (выполнен SQL скрипт)
- [ ] Workflow протестирован на 1-2 месяцах данных
- [ ] Достаточно места на диске целевого кластера
- [ ] Backup исходных данных создан (на всякий случай)

---

## 📚 Дополнительные материалы

- [KNIME Database Extension Guide](https://docs.knime.com/latest/db_extension_guide/)
- [ClickHouse JDBC Driver](https://github.com/ClickHouse/clickhouse-jdbc)
- [KNIME Loop Nodes](https://docs.knime.com/latest/analytics_platform_flow_control_guide/)

---

## 🔄 Альтернатива: Использовать KNIME Batch Executor

Если у вас **KNIME Server**, можно использовать **KNIME Batch Executor** для автоматического планирования:

1. Загрузить workflow на KNIME Server
2. Настроить расписание (например, ночью)
3. Email уведомления о завершении

---

**Автор:** Claude Code
**Дата:** 2025-01-12
**Версия:** 1.0
