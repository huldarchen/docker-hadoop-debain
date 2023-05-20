
## 编译
```shell
docker-compose build --no-cache
```

## 运行
```shell
docker-compose up -d
```

## 客户端连接hive
```
url: jdbc:hive2://${宿主机IP}:10000
```

## spark本地连接hive
resource目录增加hive-site.xml文件,插入 ${宿主机IP}替换成自己的docker机器的IP
```xml
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>hive</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://${宿主机IP}:3310/hive?useSSL=false&amp;useUnicode=true&amp;characterEncoding=UTF-8&amp;serverTimezone=UTC</value>
    </property>
    <property>
        <name>hive.server2.thrift.bind.host</name>
        <value>0.0.0.0</value>
    </property>
    <property>
        <name>datanucleus.autoCreateSchema</name>
        <value>false</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>com.mysql.cj.jdbc.Driver</value>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>Pwd@root830</value>
    </property>
</configuration>
```

namenode服务
1. web服务: namenode:9870
2. hdfs访问:namenode:9000
3. resourcemanager:namenode:8088
datanode服务
1. datanode web: datanode:9864
