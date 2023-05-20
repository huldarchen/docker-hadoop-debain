#!/usr/bin/env bash

if [ -z "$HADOOP_MODE" ]; then
    echo "HADOOP_MODE variable is not set. Exiting..."
    exit 1
fi


: <<'COMMENT'
  根据不同的模块启动对应的服务
  服务规划:
    在docker-compose.yml 指定HADOOP_MODE:namenode datanode hive
    namenode节点开启 hadoop的namenode和resourcemanager服务
    datanode节点开启 hadoop的datanode和nodemanager服务
    hive节点开启 hive服务
COMMENT
case $HADOOP_MODE in

"namenode")

  echo -e "\e[31mformat namenode...\e[0m"
  yes n | hdfs namenode -format > /dev/null 2>&1
  echo -e "\e[32mstart namenode...\e[0m"
  hdfs --daemon start namenode
  echo -e "\e[34mstart resource manager...\e[0m"
  yarn --daemon start resourcemanager
  ;;

"datanode")
  echo -e "\e[32mstart datanode (${NODE})...\e[0m"
  hdfs --daemon start datanode
  echo -e "\e[34mstart node manager (${NODE})...\e[0m"
  yarn --daemon start nodemanager
  ;;

"hive")

  hadoop fs -ls /tmp \
  || hadoop fs -mkdir /tmp \
  || hadoop fs -chmod g+w /tmp

  hadoop fs -ls /user/hive/warehouse \
   || hadoop fs -mkdir -p /user/hive/warehouse \
   || hadoop fs -chmod g+w   /user/hive/warehouse
  

  schematool -dbType mysql -validate \
  || schematool -dbType mysql -initSchema --verbose

  echo -e "start metastore"
  nohup hive --service metastore 2>&1 &

  echo -e "start hiveserver2"

  nohup hiveserver2 -hiveconf hive.server2.authentication=nosasl -hiveconf hive.server2.enable.doAs=false >/dev/null 2>&1 &
  ;;
*)
  echo "KHMT K18A"
  ;;
esac

sleep infinity