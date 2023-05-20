#!/usr/bin/env bash

function addProperty () {
  local path=$1
  local name=$2
  local value=$3

  local entry="<property>\n\t<name>$name</name>\n\t<value>$value</value>\n</property>"
  local escapedEntry
  escapedEntry=$(echo "$entry" | sed 's/\//\\\//g')
  sed -i "/<\/configuration>/ s/.*/${escapedEntry//&/\\&amp;}\n<\/configuration>/" "$path"
}

# 通过env_file来设置变量 参数: 要配置的文件路径 要配置的模块 env环境变量前缀
function configure() {
  local path=$1 #文件路径
  local module=$2 #修改的是哪一个模块 core hdfs yarn hive等
  local envPrefix=$3 #修改的值

  local var
  local value
  
  echo "Configuring $module"
  for c in $(printenv | perl -sne 'print "$1 " if m/^${envPrefix}_(.+?)=.*/' -- -envPrefix="$envPrefix"); do
    name=$(echo "${c}" | perl -pe 's/___/-/g; s/__/_/g; s/_/./g')
    var="${envPrefix}_${c}"
    value=${!var}
    echo " - Setting $name=$value"
    addProperty "$path" "$name" "$value"
  done
}

export CORE_CONF_fs_defaultFS=${CORE_CONF_fs_defaultFS:-hdfs://$(hostname -f):8020}

# dataNode
readonly NODE=$HADOOP_MODE-$(hostname -i | awk -F "." '{print $NF}' | awk '{print $1-2}')
readonly HADOOP_CONF_DIR=/etc/hadoop
readonly HIVE_CONF_DIR=/etc/hive
readonly HDFS_CACHE_DIR=file://$HADOOP_DATA_DIR/$NODE

# 配置 core-site.xml
configure $HADOOP_CONF_DIR/core-site.xml core CORE_CONF

# 配置hdfs-site.xml 这里有个问题,如果env中配置了同样的参数 就会重复
addProperty $HADOOP_CONF_DIR/hdfs-site.xml hadoop.tmp.dir $HADOOP_CONF_DIR # hadoop.tmp.dir namenode元数据信息
addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.namenode.name.dir "$HDFS_CACHE_DIR"/name
addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.namenode.checkpoint.dir "$HDFS_CACHE_DIR"/namesecondary
addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.datanode.data.dir "$HDFS_CACHE_DIR"/data
addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.webhdfs.enabled true
addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.permissions.enabled false

# 配置yarn-site.xml
addProperty $HADOOP_CONF_DIR/yarn-site.xml yarn.resourcemanager.hostname namenode

# 配置mapred-site.xml
configure $HADOOP_CONF_DIR/mapred-site.xml mapred MAPRED_CONF
# 这个变量要看下这是什么
# addProperty $HADOOP_CONF_DIR/mapred-site.xml mapreduce.application.classpath $(mapred classpath)

configure $HADOOP_CONF_DIR/httpfs-site.xml httpfs HTTPFS_CONF
configure $HADOOP_CONF_DIR/kms-site.xml kms KMS_CONF


# 修改网络
if [ "$MULTIHOMED_NETWORK" = "1" ]; then
    echo "Configuring for multihomed network"

    # HDFS
    addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.namenode.rpc-bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.namenode.servicerpc-bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.namenode.http-bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.namenode.https-bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.client.use.datanode.hostname true
    addProperty $HADOOP_CONF_DIR/hdfs-site.xml dfs.datanode.use.datanode.hostname true

    # YARN
    addProperty $HADOOP_CONF_DIR/yarn-site.xml yarn.resourcemanager.bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/yarn-site.xml yarn.nodemanager.bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/yarn-site.xml yarn.nodemanager.bind-host 0.0.0.0
    addProperty $HADOOP_CONF_DIR/yarn-site.xml yarn.timeline-service.bind-host 0.0.0.0

    # MAPRED
    addProperty $HADOOP_CONF_DIR/mapred-site.xml yarn.nodemanager.bind-host 0.0.0.0
fi

# 监控host
if [ -n "$GANGLIA_HOST" ]; then
    mv $HADOOP_CONF_DIR/hadoop-metrics.properties $HADOOP_CONF_DIR/hadoop-metrics.properties.orig
    mv $HADOOP_CONF_DIR/hadoop-metrics2.properties $HADOOP_CONF_DIR/hadoop-metrics2.properties.orig

    for module in mapred jvm rpc ugi; do
        echo "$module.class=org.apache.hadoop.metrics.ganglia.GangliaContext31"
        echo "$module.period=10"
        echo "$module.servers=$GANGLIA_HOST:8649"
    done > $HADOOP_CONF_DIR/hadoop-metrics.properties
    
    for module in namenode datanode resourcemanager nodemanager mrappmaster jobhistoryserver; do
        echo "$module.sink.ganglia.class=org.apache.hadoop.metrics2.sink.ganglia.GangliaSink31"
        echo "$module.sink.ganglia.period=10"
        echo "$module.sink.ganglia.supportsparse=true"
        echo "$module.sink.ganglia.slope=jvm.metrics.gcCount=zero,jvm.metrics.memHeapUsedM=both"
        echo "$module.sink.ganglia.dmax=jvm.metrics.threadsBlocked=70,jvm.metrics.memHeapUsedM=40"
        echo "$module.sink.ganglia.servers=$GANGLIA_HOST:8649"
    done > $HADOOP_CONF_DIR/hadoop-metrics2.properties
fi

configure $HIVE_CONF_DIR/hive-site.xml hive HIVE_SITE_CONF

# 等待应用程序 用来保证启动的顺序
function wait_for_it()
{
    local serviceport=$1
    local service=${serviceport%%:*}
    local port=${serviceport#*:}
    local retry_seconds=5
    local max_try=100
    let i=1

    nc -z $service $port
    
    result=$?

    until [ $result -eq 0 ]; do
      echo "[$i/$max_try] check for ${service}:${port}..."
      echo "[$i/$max_try] ${service}:${port} is not available yet"
      if (( $i == $max_try )); then
        echo "[$i/$max_try] ${service}:${port} is still not available; giving up after ${max_try} tries. :/"
        exit 1
      fi
      
      echo "[$i/$max_try] try in ${retry_seconds}s once again ..."
      let "i++"
      sleep $retry_seconds

      nc -z $service $port
      result=$?
    done
    echo "[$i/$max_try] $service:${port} is available."
}

for i in ${SERVICE_PRECONDITION[@]}
do
    wait_for_it ${i}
done

exec $@