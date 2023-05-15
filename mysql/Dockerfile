FROM mysql:8.0.33-debian

COPY  ./conf/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf
COPY  ./init/hive.sql /docker-entrypoint-initdb.d
