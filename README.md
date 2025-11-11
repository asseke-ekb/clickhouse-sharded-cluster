# ClickHouse Sharded Cluster (3 Shards, No Replication)

Конфигурация кластера ClickHouse из 3 шардов без репликации с поддержкой ON CLUSTER команд через ZooKeeper.

## 📋 Характеристики кластера

- **3 ClickHouse шарда** (без репликации)
- **3 ZooKeeper узла** (для координации distributed DDL)
- **Версии:** ClickHouse 24.8, ZooKeeper 3.8
- **ON CLUSTER поддержка:** Да (через ZooKeeper)
- **Шардирование:** По `sipHash64(user_id)`

## Архитектура

```
┌─────────────────────────────────────────┐
│   ZooKeeper Ensemble (DDL Coordination) │
│   ┌─────────┬─────────┬─────────┐      │
│   │  ZK-1   │  ZK-2   │  ZK-3   │      │
│   └─────────┴─────────┴─────────┘      │
└─────────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
┌───▼───┐     ┌───▼───┐     ┌───▼───┐
│Shard-1│     │Shard-2│     │Shard-3│
│ (01)  │     │ (02)  │     │ (03)  │
└───────┘     └───────┘     └───────┘
```

## 📁 Структура проекта

```
clickhouse_shard/
├── docker-compose-full.yml          # Локальное развертывание (Windows/macOS)
├── .gitignore                       # Исключения для Git
├── shard-1/
│   └── config/
│       ├── clickhouse/
│       │   ├── config.xml           # Конфигурация ClickHouse
│       │   └── users.xml            # Пользователи и права
│       └── zookeeper/
│           └── zoo.cfg              # Конфигурация ZooKeeper
├── shard-2/                          # Аналогичная структура
├── shard-3/                          # Аналогичная структура
├── setup-with-cluster.sql           # Пример ON CLUSTER команд
├── demo-tables-simple.sql           # Создание демо-таблиц
├── insert-sample-data.sql           # Вставка тестовых данных
├── PRODUCTION-DEPLOYMENT.md         # Гайд по деплою на 3 VM
├── TROUBLESHOOTING.md               # Решение проблем (Windows)
├── DBEAVER-CONNECTION.md            # Подключение через DBeaver
└── DEMO-GUIDE.md                    # Работа с демо-данными
```

## 🔧 Конфигурация

### Порты

| Сервис | HTTP | Native TCP | Interserver | Prometheus | ZooKeeper |
|--------|------|------------|-------------|------------|-----------|
| Shard-1 | 8123 | 9000 | 9009 | 9363 | 2181 |
| Shard-2 | 8124 | 9001 | 9010 | 9364 | 2182 |
| Shard-3 | 8125 | 9002 | 9011 | 9365 | 2183 |

### Пользователи

| User | Password | Права |
|------|----------|-------|
| admin | admin123 | Полные |
| dbeaver | dbeaver123 | Чтение/запись |

**⚠️ ВАЖНО:** Смените пароли в production! Отредактируйте `shard-*/config/clickhouse/users.xml`

### Кластер

- **Имя кластера:** `dwh_sharded_cluster`
- **Шарды:** 3
- **Реплики на шард:** 1 (без репликации)
- **Sharding key:** `sipHash64(user_id)`

## 🚀 Быстрый старт (Локально)

### Требования

- Docker 20.10+
- Docker Compose 2.0+
- 8 GB RAM минимум
- Порты: 8123-8125, 9000-9002, 2181-2183

### 1. Клонировать репозиторий

```bash
git clone https://github.com/your-username/clickhouse-sharded-cluster.git
cd clickhouse-sharded-cluster
```

### 2. Запустить кластер

```bash
docker-compose -f docker-compose-full.yml up -d
```

### 3. Проверить статус

```bash
# Проверить все контейнеры
docker-compose -f docker-compose-full.yml ps

# Проверить кластер
docker exec clickhouse-shard-01 clickhouse-client --query "SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster'"
```

### 4. Подключиться к кластеру

**Через DBeaver:**

- Host: `localhost`
- Port: `8123`
- User: `dbeaver`
- Password: `dbeaver123`
- Database: `default`

**Через командную строку:**

```bash
docker exec -it clickhouse-shard-01 clickhouse-client --user dbeaver --password dbeaver123
```

## 🎯 Использование ON CLUSTER

Создайте базу данных и таблицы на всех шардах одной командой:

```sql
-- Создать базу на всех шардах
CREATE DATABASE IF NOT EXISTS mydb ON CLUSTER 'dwh_sharded_cluster';

-- Создать локальную таблицу на каждом шарде
CREATE TABLE mydb.events_local ON CLUSTER 'dwh_sharded_cluster' (
    event_id UUID,
    user_id UInt64,
    event_type String,
    event_time DateTime
)
ENGINE = MergeTree()
ORDER BY (user_id, event_time);

-- Создать distributed таблицу (на одном узле)
CREATE TABLE mydb.events_distributed AS mydb.events_local
ENGINE = Distributed('dwh_sharded_cluster', 'mydb', 'events_local', sipHash64(user_id));
```

## 📊 Демо-данные

### Создать структуру таблиц

```bash
# Выполните через DBeaver или:
docker exec -i clickhouse-shard-01 clickhouse-client --user=dbeaver --password=dbeaver123 --multiquery < demo-tables-simple.sql
```

### Вставить тестовые данные

Откройте [insert-sample-data.sql](insert-sample-data.sql) в DBeaver и выполняйте блоками (10-20 записей за раз).

### Проверить распределение по шардам

```sql
SELECT
    _shard_num as shard,
    count() as rows
FROM demo.users_distributed
GROUP BY _shard_num;
```

Подробности в [DEMO-GUIDE.md](DEMO-GUIDE.md).

## 🖥️ Production деплой на 3 VM

Для развертывания на реальных серверах см. подробную инструкцию: [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md)

**Требования:**

- 3 VM с Ubuntu 20.04+ / CentOS 8+
- Docker и Docker Compose на каждой
- Сетевой доступ между VM (порты 8123, 9000, 9009, 2181-2888-3888)

**Краткая инструкция:**

1. Настроить IP адреса в файлах `config.xml` на каждом шарде
2. Скопировать файлы на соответствующие VM
3. Запустить Docker Compose на каждой VM
4. Проверить кластер

## 📝 Полезные команды

### Управление кластером

```bash
# Запуск
docker-compose -f docker-compose-full.yml up -d

# Остановка
docker-compose -f docker-compose-full.yml down

# Логи
docker-compose -f docker-compose-full.yml logs -f clickhouse-shard-01

# Перезапуск конкретного сервиса
docker-compose -f docker-compose-full.yml restart clickhouse-shard-01
```

### SQL команды

```sql
-- Проверить кластер
SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster';

-- Проверить ZooKeeper
SELECT * FROM system.zookeeper WHERE path = '/';

-- Список баз на всех шардах
SHOW DATABASES;

-- Размер данных по шардам
SELECT
    _shard_num,
    count() as rows,
    formatReadableSize(sum(data_compressed_bytes)) as size
FROM system.parts
WHERE active
GROUP BY _shard_num;
```

## 🐛 Troubleshooting

### Проблема с INSERT на Windows

Если получаете ошибку `transport error: 500` при вставке данных на Windows:

- **Причина:** Проблема с правами доступа к bind mounts в Docker на Windows
- **Решение:** Используйте маленькие порции данных (10-20 записей) или Docker volumes

Подробности: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

### ZooKeeper не запускается

```bash
# Проверить логи
docker logs zookeeper-1

# Очистить данные ZooKeeper (ВНИМАНИЕ: удалит все метаданные!)
docker-compose -f docker-compose-full.yml down -v
```

### ClickHouse не может подключиться к ZooKeeper

```bash
# Проверить доступность ZooKeeper
echo ruok | nc localhost 2181

# Должен вернуть: imok
```

## 📚 Документация

- [Официальная документация ClickHouse](https://clickhouse.com/docs)
- [ClickHouse Distributed Tables](https://clickhouse.com/docs/en/engines/table-engines/special/distributed)
- [ON CLUSTER Queries](https://clickhouse.com/docs/en/sql-reference/distributed-ddl)
- [PRODUCTION-DEPLOYMENT.md](PRODUCTION-DEPLOYMENT.md) - Полное руководство по деплою
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Решение проблем
- [DEMO-GUIDE.md](DEMO-GUIDE.md) - Работа с демо-данными

## 🔐 Безопасность

- Смените пароли в `users.xml` перед production деплоем
- Настройте firewall правила между узлами
- Используйте TLS для межсервисного взаимодействия
- Ограничьте сетевые доступы (`<networks>` в users.xml)

## 📄 Лицензия

MIT

## 🤝 Контакты

По вопросам и предложениям создавайте Issues в GitHub.
