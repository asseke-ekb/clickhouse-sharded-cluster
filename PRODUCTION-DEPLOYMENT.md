# Развертывание ClickHouse кластера на 3 виртуальных машинах

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                  Production Cluster                      │
│              3 Shards with ZooKeeper                     │
└─────────────────────────────────────────────────────────┘

VM-1 (192.168.X.10)          VM-2 (192.168.X.11)          VM-3 (192.168.X.12)
├─ ClickHouse Shard-1        ├─ ClickHouse Shard-2        ├─ ClickHouse Shard-3
└─ ZooKeeper Node-1          └─ ZooKeeper Node-2          └─ ZooKeeper Node-3
```

**Каждая VM содержит:**
- 1 ClickHouse узел (один из 3 шардов)
- 1 ZooKeeper узел (для координации кластера)

---

## Требования к виртуальным машинам

### Минимальные требования на VM:

| Параметр | Минимум | Рекомендуется |
|----------|---------|---------------|
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 8 GB | 16+ GB |
| **Disk** | 100 GB | 500+ GB (SSD) |
| **OS** | Ubuntu 20.04+ | Ubuntu 22.04 LTS |
| **Network** | 1 Gbps | 10 Gbps |

### Сетевые настройки:

**Предполагаемые IP адреса:**
- VM-1: `192.168.9.110` (замените на ваш)
- VM-2: `192.168.9.111` (замените на ваш)
- VM-3: `192.168.9.112` (замените на ваш)

**Открытые порты:**
- `8123` - ClickHouse HTTP
- `9000` - ClickHouse Native TCP
- `9009` - ClickHouse Interserver
- `9363` - Prometheus metrics
- `2181` - ZooKeeper client
- `2888` - ZooKeeper peer
- `3888` - ZooKeeper leader election

---

## Шаг 1: Подготовка всех VM

Выполните на **КАЖДОЙ** из 3 виртуальных машин:

```bash
# Обновить систему
sudo apt update && sudo apt upgrade -y

# Установить необходимые пакеты
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Установить Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Установить Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Добавить текущего пользователя в группу docker
sudo usermod -aG docker $USER

# Применить изменения группы (или перелогиньтесь)
newgrp docker

# Проверить установку
docker --version
docker-compose --version

# Настроить firewall (если используется)
sudo ufw allow 8123/tcp    # ClickHouse HTTP
sudo ufw allow 9000/tcp    # ClickHouse TCP
sudo ufw allow 9009/tcp    # Interserver
sudo ufw allow 9363/tcp    # Metrics
sudo ufw allow 2181/tcp    # ZooKeeper client
sudo ufw allow 2888/tcp    # ZooKeeper peer
sudo ufw allow 3888/tcp    # ZooKeeper election
sudo ufw allow 22/tcp      # SSH
sudo ufw enable

# Синхронизация времени (важно!)
sudo apt install -y chrony
sudo systemctl enable chrony
sudo systemctl start chrony
```

---

## Шаг 2: Создание директорий на каждой VM

На **VM-1:**
```bash
mkdir -p /opt/clickhouse-cluster/shard-1/{config/clickhouse,data/clickhouse,logs/clickhouse,data/zookeeper,logs/zookeeper}
cd /opt/clickhouse-cluster/shard-1
```

На **VM-2:**
```bash
mkdir -p /opt/clickhouse-cluster/shard-2/{config/clickhouse,data/clickhouse,logs/clickhouse,data/zookeeper,logs/zookeeper}
cd /opt/clickhouse-cluster/shard-2
```

На **VM-3:**
```bash
mkdir -p /opt/clickhouse-cluster/shard-3/{config/clickhouse,data/clickhouse,logs/clickhouse,data/zookeeper,logs/zookeeper}
cd /opt/clickhouse-cluster/shard-3
```

---

## Шаг 3: Конфигурационные файлы

### VM-1: docker-compose.yml

Создайте файл `/opt/clickhouse-cluster/shard-1/docker-compose.yml`:

```yaml
version: '3.8'

services:
  zookeeper-1:
    image: zookeeper:3.8
    container_name: zookeeper-1
    hostname: zookeeper-1
    network_mode: host
    environment:
      ZOO_MY_ID: 1
      ZOO_SERVERS: server.1=0.0.0.0:2888:3888;2181 server.2=192.168.9.111:2888:3888;2181 server.3=192.168.9.112:2888:3888;2181
      ZOO_TICK_TIME: 2000
      ZOO_INIT_LIMIT: 10
      ZOO_SYNC_LIMIT: 5
      ZOO_MAX_CLIENT_CNXNS: 0
      ZOO_AUTOPURGE_PURGEINTERVAL: 24
      ZOO_AUTOPURGE_SNAPRETAINCOUNT: 7
      ZOO_4LW_COMMANDS_WHITELIST: srvr,mntr,ruok,stat
    volumes:
      - ./data/zookeeper:/data
      - ./logs/zookeeper:/datalog
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "echo ruok | nc localhost 2181 | grep imok"]
      interval: 10s
      timeout: 5s
      retries: 3

  clickhouse-shard-01:
    image: clickhouse/clickhouse-server:24.8
    container_name: clickhouse-shard-01
    hostname: clickhouse-shard-01
    network_mode: host
    environment:
      CLICKHOUSE_DB: default
    volumes:
      - ./data/clickhouse:/var/lib/clickhouse
      - ./logs/clickhouse:/var/log/clickhouse-server
      - ./config/clickhouse/config.xml:/etc/clickhouse-server/config.d/config.xml:ro
      - ./config/clickhouse/users.xml:/etc/clickhouse-server/users.xml:ro
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    restart: unless-stopped
    depends_on:
      zookeeper-1:
        condition: service_healthy
```

### VM-1: config.xml

Создайте файл `/opt/clickhouse-cluster/shard-1/config/clickhouse/config.xml`:

```xml
<clickhouse>
    <!-- Network Settings -->
    <listen_host>0.0.0.0</listen_host>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <interserver_http_port>9009</interserver_http_port>

    <!-- Prometheus metrics -->
    <prometheus>
        <endpoint>/metrics</endpoint>
        <port>9363</port>
        <metrics>true</metrics>
        <events>true</events>
        <asynchronous_metrics>true</asynchronous_metrics>
    </prometheus>

    <!-- ZooKeeper Configuration -->
    <zookeeper>
        <node>
            <host>192.168.9.110</host>
            <port>2181</port>
        </node>
        <node>
            <host>192.168.9.111</host>
            <port>2181</port>
        </node>
        <node>
            <host>192.168.9.112</host>
            <port>2181</port>
        </node>
        <session_timeout_ms>30000</session_timeout_ms>
        <operation_timeout_ms>10000</operation_timeout_ms>
    </zookeeper>

    <!-- Macros -->
    <macros>
        <shard>01</shard>
        <cluster>dwh_sharded_cluster</cluster>
    </macros>

    <!-- Remote Servers (Cluster) -->
    <remote_servers>
        <dwh_sharded_cluster>
            <shard>
                <internal_replication>false</internal_replication>
                <replica>
                    <host>192.168.9.110</host>
                    <port>9000</port>
                </replica>
            </shard>
            <shard>
                <internal_replication>false</internal_replication>
                <replica>
                    <host>192.168.9.111</host>
                    <port>9000</port>
                </replica>
            </shard>
            <shard>
                <internal_replication>false</internal_replication>
                <replica>
                    <host>192.168.9.112</host>
                    <port>9000</port>
                </replica>
            </shard>
        </dwh_sharded_cluster>
    </remote_servers>

    <!-- Memory Settings -->
    <max_server_memory_usage_to_ram_ratio>0.9</max_server_memory_usage_to_ram_ratio>
    <max_concurrent_queries>100</max_concurrent_queries>
    <max_connections>1024</max_connections>
    <mark_cache_size>5368709120</mark_cache_size>
    <uncompressed_cache_size>10737418240</uncompressed_cache_size>

    <!-- MergeTree Settings -->
    <merge_tree>
        <max_bytes_to_merge_at_max_space_in_pool>161061273600</max_bytes_to_merge_at_max_space_in_pool>
        <max_replicated_merges_in_queue>32</max_replicated_merges_in_queue>
    </merge_tree>

    <!-- Background Operations -->
    <background_pool_size>32</background_pool_size>
    <background_schedule_pool_size>128</background_schedule_pool_size>

    <!-- Compression -->
    <compression>
        <case>
            <method>zstd</method>
            <level>3</level>
        </case>
    </compression>

    <!-- Logging -->
    <logger>
        <level>information</level>
        <log>/var/log/clickhouse-server/clickhouse-server.log</log>
        <errorlog>/var/log/clickhouse-server/clickhouse-server.err.log</errorlog>
        <size>1000M</size>
        <count>10</count>
    </logger>

    <!-- Query Log -->
    <query_log>
        <database>system</database>
        <table>query_log</table>
        <partition_by>toYYYYMM(event_date)</partition_by>
        <ttl>event_date + INTERVAL 30 DAY</ttl>
    </query_log>

    <!-- Distributed DDL -->
    <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
    </distributed_ddl>

    <!-- Timezone -->
    <timezone>UTC</timezone>

    <!-- Paths -->
    <path>/var/lib/clickhouse/</path>
    <tmp_path>/var/lib/clickhouse/tmp/</tmp_path>
    <user_files_path>/var/lib/clickhouse/user_files/</user_files_path>
</clickhouse>
```

### VM-1, VM-2, VM-3: users.xml (одинаковый для всех)

Создайте файл `/opt/clickhouse-cluster/shard-X/config/clickhouse/users.xml`:

```xml
<?xml version="1.0"?>
<clickhouse>
    <users>
        <admin>
            <password>admin123</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </admin>

        <dbeaver>
            <password>dbeaver123</password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </dbeaver>

        <default>
            <password></password>
            <networks>
                <ip>::1</ip>
                <ip>127.0.0.1</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
        </default>
    </users>

    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>random</load_balancing>
            <max_execution_time>300</max_execution_time>
        </default>
    </profiles>

    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
```

---

## Шаг 4: Различия между VM

### VM-2 и VM-3 конфигурация

Для **VM-2** и **VM-3** используйте те же файлы, но замените:

#### VM-2 docker-compose.yml:
- `ZOO_MY_ID: 2`
- `ZOO_SERVERS: server.1=192.168.9.110:2888:3888;2181 server.2=0.0.0.0:2888:3888;2181 server.3=192.168.9.112:2888:3888;2181`
- `container_name: zookeeper-2`
- `container_name: clickhouse-shard-02`

#### VM-2 config.xml:
- `<shard>02</shard>`

#### VM-3 docker-compose.yml:
- `ZOO_MY_ID: 3`
- `ZOO_SERVERS: server.1=192.168.9.110:2888:3888;2181 server.2=192.168.9.111:2888:3888;2181 server.3=0.0.0.0:2888:3888;2181`
- `container_name: zookeeper-3`
- `container_name: clickhouse-shard-03`

#### VM-3 config.xml:
- `<shard>03</shard>`

---

## Шаг 5: Запуск кластера

### На каждой VM последовательно:

```bash
# VM-1
cd /opt/clickhouse-cluster/shard-1
docker-compose up -d

# Подождать 30 секунд

# VM-2
cd /opt/clickhouse-cluster/shard-2
docker-compose up -d

# Подождать 30 секунд

# VM-3
cd /opt/clickhouse-cluster/shard-3
docker-compose up -d
```

---

## Шаг 6: Проверка работоспособности

### На VM-1:

```bash
# Проверить контейнеры
docker ps

# Проверить ClickHouse
docker exec clickhouse-shard-01 clickhouse-client --query "SELECT version()"

# Проверить кластер
docker exec clickhouse-shard-01 clickhouse-client --query "SELECT * FROM system.clusters WHERE cluster = 'dwh_sharded_cluster'"

# Проверить ZooKeeper
docker exec zookeeper-1 sh -c "echo ruok | nc localhost 2181"
```

### Проверка с внешней машины:

```bash
# Проверить доступность
curl http://192.168.9.110:8123/
curl http://192.168.9.111:8123/
curl http://192.168.9.112:8123/

# Выполнить запрос
curl "http://192.168.9.110:8123/?query=SELECT+version()"
```

---

## Шаг 7: Создание тестовых таблиц

Подключитесь к **VM-1** и выполните:

```bash
docker exec -it clickhouse-shard-01 clickhouse-client
```

```sql
-- Создать БД на всех шардах
CREATE DATABASE IF NOT EXISTS demo ON CLUSTER 'dwh_sharded_cluster';

-- Создать локальную таблицу на всех шардах
CREATE TABLE IF NOT EXISTS demo.users_local ON CLUSTER 'dwh_sharded_cluster' (
    user_id UInt64,
    username String,
    email String,
    country String,
    created_at DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY user_id;

-- Создать Distributed таблицу (только на текущем узле)
CREATE TABLE IF NOT EXISTS demo.users_distributed AS demo.users_local
ENGINE = Distributed('dwh_sharded_cluster', 'demo', 'users_local', sipHash64(user_id));

-- Вставить тестовые данные
INSERT INTO demo.users_distributed
SELECT
    number as user_id,
    concat('user_', toString(number)) as username,
    concat('user', toString(number), '@example.com') as email,
    arrayElement(['USA', 'UK', 'Canada'], (number % 3) + 1) as country,
    now() as created_at
FROM numbers(100);

-- Проверить распределение по шардам
SELECT
    _shard_num as shard,
    count() as rows
FROM demo.users_distributed
GROUP BY _shard_num
ORDER BY _shard_num;
```

---

## Подключение из DBeaver

**Подключение к кластеру через VM-1:**
```
Host: 192.168.9.110
Port: 8123
Database: default
User: dbeaver
Password: dbeaver123
```

Можно создать 3 подключения (к каждой VM отдельно) для просмотра данных на конкретных шардах.

---

## Мониторинг

### Логи ClickHouse:

```bash
# VM-1
docker logs clickhouse-shard-01 --tail 100 -f

# VM-2
docker logs clickhouse-shard-02 --tail 100 -f

# VM-3
docker logs clickhouse-shard-03 --tail 100 -f
```

### Метрики Prometheus:

```bash
curl http://192.168.9.110:9363/metrics
curl http://192.168.9.111:9363/metrics
curl http://192.168.9.112:9363/metrics
```

---

## Backup

### Создание backup:

```bash
# На каждой VM
docker-compose -f /opt/clickhouse-cluster/shard-X/docker-compose.yml stop clickhouse-shard-0X
tar -czf /backup/clickhouse-shard-X-$(date +%Y%m%d).tar.gz /opt/clickhouse-cluster/shard-X/data/
docker-compose -f /opt/clickhouse-cluster/shard-X/docker-compose.yml start clickhouse-shard-0X
```

---

## Автоматический деплой скрипт

Создайте файл `deploy.sh`:

```bash
#!/bin/bash
# Скрипт развертывания на VM

VM_IP=$1
SHARD_NUM=$2

if [ -z "$VM_IP" ] || [ -z "$SHARD_NUM" ]; then
    echo "Usage: ./deploy.sh <VM_IP> <SHARD_NUM>"
    exit 1
fi

echo "Deploying to VM: $VM_IP, Shard: $SHARD_NUM"

# Копировать файлы на VM
scp -r shard-${SHARD_NUM}/* root@${VM_IP}:/opt/clickhouse-cluster/shard-${SHARD_NUM}/

# Запустить Docker Compose
ssh root@${VM_IP} "cd /opt/clickhouse-cluster/shard-${SHARD_NUM} && docker-compose up -d"

echo "Deployment complete!"
```

Использование:
```bash
chmod +x deploy.sh
./deploy.sh 192.168.9.110 1
./deploy.sh 192.168.9.111 2
./deploy.sh 192.168.9.112 3
```

---

**Готово!** Теперь у вас есть полная инструкция для развертывания на 3 реальных VM. 🚀
