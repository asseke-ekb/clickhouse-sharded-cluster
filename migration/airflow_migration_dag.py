"""
Airflow DAG для миграции medical_services из монолитного ClickHouse в шардированный кластер
с использованием ReplacingMergeTree для автоматической дедупликации версий.

Автор: Claude Code
Дата: 2025-01-12
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup
import logging

# =====================================================
# Конфигурация
# =====================================================

SOURCE_CLICKHOUSE_CONN_ID = 'clickhouse_source'  # 192.168.9.15
TARGET_CLICKHOUSE_CONN_ID = 'clickhouse_cluster'  # Ваш новый кластер

# Параметры батчинга
BATCH_SIZE = 500000  # Размер батча (500k записей)
START_DATE = '2020-01-01'  # Начальная дата миграции
END_DATE = '2025-01-12'  # Конечная дата миграции

# =====================================================
# DAG Definition
# =====================================================

default_args = {
    'owner': 'data_engineering',
    'depends_on_past': False,
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=5),
    'execution_timeout': timedelta(hours=6),
}

dag = DAG(
    'medical_services_migration_to_cluster',
    default_args=default_args,
    description='Миграция medical_services в 4-shard ClickHouse кластер с ReplacingMergeTree',
    schedule_interval=None,  # Запуск вручную
    start_date=datetime(2025, 1, 12),
    catchup=False,
    tags=['migration', 'clickhouse', 'medical_services'],
)

# =====================================================
# Task 1: Проверка исходных данных
# =====================================================

check_source_data = SQLExecuteQueryOperator(
    task_id='check_source_data',
    conn_id=SOURCE_CLICKHOUSE_CONN_ID,
    sql="""
        SELECT
            'medical_services' as table_name,
            count() as total_rows,
            count(DISTINCT id) as unique_ids,
            min(service_date) as min_date,
            max(service_date) as max_date,
            max(version) as max_version
        FROM outpatient.medical_services

        UNION ALL

        SELECT
            'medical_service_registers' as table_name,
            count() as total_rows,
            count(DISTINCT id) as unique_ids,
            min(insert_date_clickhouse) as min_date,
            max(insert_date_clickhouse) as max_date,
            max(version) as max_version
        FROM outpatient.medical_service_registers
    """,
    dag=dag,
)

# =====================================================
# Task 2: Создание схемы на кластере
# =====================================================

create_target_schema = SQLExecuteQueryOperator(
    task_id='create_target_schema',
    conn_id=TARGET_CLICKHOUSE_CONN_ID,
    sql='migration/medical-services-schema.sql',  # Созданный ранее файл
    dag=dag,
)

# =====================================================
# Task 3: Миграция medical_services (батчами по месяцам)
# =====================================================

def generate_monthly_batches(start_date: str, end_date: str):
    """Генерация списка месяцев для батчинга"""
    from dateutil.relativedelta import relativedelta
    from datetime import datetime

    start = datetime.strptime(start_date, '%Y-%m-%d')
    end = datetime.strptime(end_date, '%Y-%m-%d')

    batches = []
    current = start
    while current <= end:
        batch_start = current.strftime('%Y-%m-%d')
        next_month = current + relativedelta(months=1)
        batch_end = next_month.strftime('%Y-%m-%d')
        batches.append((batch_start, batch_end))
        current = next_month

    return batches

with TaskGroup('migrate_medical_services', dag=dag) as migrate_medical_services_group:

    # Получаем список батчей
    batches = generate_monthly_batches(START_DATE, END_DATE)

    for idx, (batch_start, batch_end) in enumerate(batches):

        # Миграция одного месяца данных
        migrate_batch = SQLExecuteQueryOperator(
            task_id=f'migrate_medical_services_{batch_start.replace("-", "_")}',
            conn_id=TARGET_CLICKHOUSE_CONN_ID,
            sql=f"""
                INSERT INTO outpatient.medical_services
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
                FROM remote(
                    '192.168.9.15:9000',
                    'outpatient.medical_services',
                    'default',
                    ''
                )
                WHERE service_date >= toDate('{batch_start}')
                  AND service_date < toDate('{batch_end}')
                SETTINGS max_execution_time = 3600, max_block_size = 100000
            """,
        )

# =====================================================
# Task 4: Миграция medical_service_registers (батчами)
# =====================================================

with TaskGroup('migrate_medical_service_registers', dag=dag) as migrate_registers_group:

    batches = generate_monthly_batches(START_DATE, END_DATE)

    for idx, (batch_start, batch_end) in enumerate(batches):

        migrate_registers_batch = SQLExecuteQueryOperator(
            task_id=f'migrate_registers_{batch_start.replace("-", "_")}',
            conn_id=TARGET_CLICKHOUSE_CONN_ID,
            sql=f"""
                INSERT INTO outpatient.medical_service_registers
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
                FROM remote(
                    '192.168.9.15:9000',
                    'outpatient.medical_service_registers',
                    'default',
                    ''
                )
                WHERE insert_date_clickhouse >= toDateTime('{batch_start}')
                  AND insert_date_clickhouse < toDateTime('{batch_end}')
                SETTINGS max_execution_time = 3600, max_block_size = 100000
            """,
        )

# =====================================================
# Task 5: Принудительная дедупликация (OPTIMIZE TABLE)
# =====================================================

optimize_medical_services = SQLExecuteQueryOperator(
    task_id='optimize_medical_services',
    conn_id=TARGET_CLICKHOUSE_CONN_ID,
    sql="""
        OPTIMIZE TABLE outpatient.medical_services_local ON CLUSTER 'dwh_sharded_cluster' FINAL;
    """,
    dag=dag,
)

optimize_registers = SQLExecuteQueryOperator(
    task_id='optimize_registers',
    conn_id=TARGET_CLICKHOUSE_CONN_ID,
    sql="""
        OPTIMIZE TABLE outpatient.medical_service_registers_local ON CLUSTER 'dwh_sharded_cluster' FINAL;
    """,
    dag=dag,
)

# =====================================================
# Task 6: Верификация данных
# =====================================================

verify_migration = SQLExecuteQueryOperator(
    task_id='verify_migration',
    conn_id=TARGET_CLICKHOUSE_CONN_ID,
    sql="""
        -- Проверка количества записей на кластере
        SELECT
            'medical_services' as table_name,
            'cluster' as source,
            count() as total_rows,
            count(DISTINCT id) as unique_ids
        FROM outpatient.medical_services

        UNION ALL

        SELECT
            'medical_services_actual' as table_name,
            'cluster_with_final' as source,
            count() as total_rows,
            count(DISTINCT id) as unique_ids
        FROM outpatient.medical_services_actual

        UNION ALL

        SELECT
            'medical_service_registers' as table_name,
            'cluster' as source,
            count() as total_rows,
            count(DISTINCT id) as unique_ids
        FROM outpatient.medical_service_registers

        UNION ALL

        SELECT
            'medical_service_registers_actual' as table_name,
            'cluster_with_final' as source,
            count() as total_rows,
            count(DISTINCT id) as unique_ids
        FROM outpatient.medical_service_registers_actual;

        -- Проверка распределения по шардам
        SELECT
            _shard_num as shard,
            count() as rows_count,
            formatReadableSize(sum(bytes_on_disk)) as size_on_disk
        FROM outpatient.medical_services
        GROUP BY _shard_num
        ORDER BY _shard_num;
    """,
    dag=dag,
)

# =====================================================
# Task Dependencies
# =====================================================

check_source_data >> create_target_schema
create_target_schema >> migrate_medical_services_group
create_target_schema >> migrate_registers_group

migrate_medical_services_group >> optimize_medical_services
migrate_registers_group >> optimize_registers

[optimize_medical_services, optimize_registers] >> verify_migration


# =====================================================
# Примечания по использованию
# =====================================================

"""
1. Настройка Airflow Connections:

   a) Исходный ClickHouse (192.168.9.15):
      - Connection Id: clickhouse_source
      - Connection Type: ClickHouse
      - Host: 192.168.9.15
      - Port: 9000 (native) или 8123 (http)
      - Login: default
      - Password: (ваш пароль)

   b) Целевой кластер:
      - Connection Id: clickhouse_cluster
      - Host: (IP любого узла кластера)
      - Port: 8123
      - Login: dbeaver
      - Password: dbeaver123

2. Установка зависимостей:
   pip install apache-airflow-providers-common-sql
   pip install clickhouse-connect

3. Запуск миграции:
   - Перейдите в Airflow UI
   - Найдите DAG: medical_services_migration_to_cluster
   - Нажмите "Trigger DAG"
   - Мониторьте прогресс в Graph View

4. Мониторинг:
   - Следите за логами каждой задачи
   - Проверяйте размер данных на шардах
   - После завершения сравните count() на source и target

5. Rollback (если нужно):
   DROP TABLE outpatient.medical_services ON CLUSTER 'dwh_sharded_cluster';
   DROP TABLE outpatient.medical_service_registers ON CLUSTER 'dwh_sharded_cluster';

6. После успешной миграции:
   - Переключите приложения на новый кластер
   - Настройте репликацию изменений (CDC) если нужно
   - Удалите старые данные на 192.168.9.15 после проверки
"""
