# KNIME Migration - Быстрый старт

Минималистичный workflow для миграции medical_services за 30 минут.

## 🚀 Самый простой вариант (без Loop)

Если нужно быстро начать, используйте этот простой workflow:

```
┌───────────────────────────────────┐
│  1. Database Connector (Source)   │  ← 192.168.9.15
└───────────────┬───────────────────┘
                │
┌───────────────▼───────────────────┐
│  2. Database Connector (Target)   │  ← Ваш кластер
└───────────────┬───────────────────┘
                │
┌───────────────▼───────────────────┐
│  3. DB Table Reader               │  ← Читать из source
│     (medical_services)            │     с LIMIT для теста
└───────────────┬───────────────────┘
                │
┌───────────────▼───────────────────┐
│  4. DB Writer                     │  ← Писать в target
│     (outpatient.medical_services) │
└───────────────────────────────────┘
```

---

## 📝 Конфигурация узлов (Copy-Paste)

### Узел 1: Database Connector (Source)

**Connection Settings:**
```
Database Type: Generic JDBC
JDBC Driver: com.clickhouse.jdbc.ClickHouseDriver
JDBC URL: jdbc:clickhouse://192.168.9.15:8123/outpatient
Username: default
Password: <ваш пароль>
```

**Advanced Settings:**
```
socket_timeout=600000
connect_timeout=60000
```

---

### Узел 2: Database Connector (Target)

**Connection Settings:**
```
Database Type: Generic JDBC
JDBC Driver: com.clickhouse.jdbc.ClickHouseDriver
JDBC URL: jdbc:clickhouse://192.168.9.110:8123/outpatient
Username: admin
Password: admin123
```

**Advanced Settings:**
```
socket_timeout=600000
```

---

### Узел 3: DB Table Reader (Source)

**SQL Query:**
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
WHERE service_date >= '2024-01-01'  -- Для теста: только 2024 год
  AND service_date < '2024-02-01'   -- Для теста: только январь
LIMIT 100000  -- Для теста: первые 100k записей
```

**⚠️ Для полной миграции:**
- Убрать `LIMIT`
- Изменить даты или убрать фильтр `WHERE`

---

### Узел 4: DB Writer (Target)

**Settings:**
```
Database Table: outpatient.medical_services
Write mode: Append
Batch size: 10000
```

**⚠️ Важно:**
- Таблица `outpatient.medical_services` должна быть уже создана на кластере
- Выполните сначала SQL скрипт: `migration/medical-services-schema.sql`

---

## ⚡ Запуск миграции

### Шаг 1: Создать схему на кластере

Выполните один раз перед запуском KNIME:

```bash
# Подключиться к кластеру
docker exec -it clickhouse-shard-01 clickhouse-client --user admin --password admin123

# Выполнить SQL скрипт
clickhouse-client --multiquery < migration/medical-services-schema.sql
```

### Шаг 2: Создать workflow в KNIME

1. Откройте KNIME Analytics Platform
2. **File → New → New KNIME Workflow**
3. Название: `Medical Services Migration`
4. Перетащите узлы из Node Repository:
   - `Database Connector` (2 раза)
   - `DB Table Reader`
   - `DB Writer`
5. Соедините узлы стрелками
6. Настройте каждый узел (см. конфигурации выше)

### Шаг 3: Тестовый запуск

1. **Правой кнопкой на DB Table Reader → Execute**
2. **Правой кнопкой на DB Table Reader → View: Table**
   - Проверьте, что данные читаются корректно
3. **Правой кнопкой на DB Writer → Execute**
4. Дождитесь завершения (progress bar)

### Шаг 4: Проверка

Выполните на кластере:

```sql
-- Проверить, что данные записались
SELECT count() as migrated_rows
FROM outpatient.medical_services;

-- Проверить распределение по шардам
SELECT _shard_num, count() as rows
FROM outpatient.medical_services
GROUP BY _shard_num;
```

---

## 🔄 Для полной миграции: Добавить Loop

Если тестовый вариант работает, добавьте Loop для батчинга:

```
[Table Creator: Months]
    │
    ├─→ [Group Loop Start]
    │       │
    │       ├─→ [DB Query Reader] (с WHERE по датам)
    │       │
    │       ├─→ [DB Writer]
    │       │
    │       └─→ [Variable Loop End]
    │
    └─→ [Table View: Progress]
```

### Table Creator для месяцев

**Manually Defined:**

| year_month | start_date | end_date   |
|------------|------------|------------|
| 2020-01    | 2020-01-01 | 2020-02-01 |
| 2020-02    | 2020-02-01 | 2020-03-01 |
| 2020-03    | 2020-03-01 | 2020-04-01 |
| ...        | ...        | ...        |
| 2025-01    | 2025-01-01 | 2025-02-01 |

Или используйте **Python Script** для генерации (см. KNIME-MIGRATION-GUIDE.md)

### DB Query Reader (внутри Loop)

**SQL с переменными:**
```sql
SELECT * FROM outpatient.medical_services
WHERE service_date >= toDate('${start_date}')
  AND service_date < toDate('${end_date}')
```

**Flow Variables:**
- На узле → Configure → Flow Variables
- Добавить: `start_date`, `end_date` из таблицы месяцев

---

## 📊 Мониторинг прогресса

### Добавить узел для логирования

**Java Snippet (после DB Writer):**

```java
// Логирование
int rowCount = inData[0].getRowCount();
String month = getVariable("year_month", "string");

System.out.println("✓ Migrated month: " + month + " - " + rowCount + " rows");

// Передать данные дальше
return inData;
```

---

## 🎯 Оценка времени миграции

**Тестовые данные:**
- 100k записей → ~2-3 минуты
- 1M записей → ~15-20 минут
- 10M записей → ~2-3 часа

**Для 50M+ записей:**
- Используйте батчинг по месяцам (Loop)
- Ожидаемое время: 4-6 часов

---

## ⚙️ Настройка производительности

### 1. Увеличить Batch Size

В узле **DB Writer**:
```
Batch size: 50000  (вместо 10000)
```

### 2. Увеличить память KNIME

Отредактируйте `knime.ini`:
```
-Xmx8g
```

### 3. Использовать параллельные workflow

Запустите 2-3 KNIME workflow параллельно:
- Workflow 1: 2020-2022
- Workflow 2: 2023-2024
- Workflow 3: 2025

---

## ✅ Checklist

### Перед запуском:
- [ ] ClickHouse JDBC драйвер установлен
- [ ] Database Connectors настроены
- [ ] Схема создана на кластере (выполнен SQL)
- [ ] Тестовый запуск выполнен успешно (100k записей)

### После миграции:
- [ ] Количество записей совпадает (source vs target)
- [ ] Распределение по шардам равномерное (~25% на каждом)
- [ ] Выполнен OPTIMIZE TABLE для дедупликации
- [ ] Приложения переключены на новый кластер

---

## 🐛 Частые ошибки

### Ошибка: "Table doesn't exist"

**Решение:**
```sql
-- Выполните на кластере:
CREATE DATABASE IF NOT EXISTS outpatient ON CLUSTER 'dwh_sharded_cluster';
```

### Ошибка: "Connection timeout"

**Решение:**
- Увеличьте таймауты в JDBC URL:
```
jdbc:clickhouse://192.168.9.15:8123/outpatient?socket_timeout=600000
```

### Ошибка: "Out of memory"

**Решение:**
- Уменьшите Batch size до 5000
- Увеличьте память KNIME в `knime.ini`

---

## 📚 Следующие шаги

1. **Полное руководство:** [KNIME-MIGRATION-GUIDE.md](KNIME-MIGRATION-GUIDE.md)
2. **Схема таблиц:** [medical-services-schema.sql](medical-services-schema.sql)
3. **Тестовые запросы:** [test-queries.sql](test-queries.sql)

---

**Автор:** Claude Code
**Дата:** 2025-01-12
