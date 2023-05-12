FROM debian:11

ENV USER=root
# 目录设计:
# /opt : 工作目录 存放下载解压的hadoop hive文件
# /etc : 存放配置文件,通过软连接的方式创建 有如下: /etc/hadoop /etc/hive

# 1. 更换为清华数据源
RUN sed -i s@/deb.debian.org/@/mirrors.tuna.tsinghua.edu.cn/@g /etc/apt/sources.list
RUN sed -i s@/security.debian.org@/mirrors.tuna.tsinghua.edu.cn/@g /etc/apt/sources.list
# 2. 安装必要依赖
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openjdk-11-jdk \
        net-tools \
        curl \
        netcat \
        gnupg \
        libsnappy-dev \
        libssl-dev \
        procps \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dist.apache.org/repos/dist/release/hadoop/common/KEYS | gpg --import -

# 3.版本变量 Allow buildtime config of HIVE_VERSION HADOOP_VERSION
# Set HIVE_VERSION HADOOP_VERSION from arg if provided at build, env if provided at run, or default
# https://docs.docker.com/engine/reference/builder/#using-arg-variables
# https://docs.docker.com/engine/reference/builder/#environment-replacement
ARG HIVE_VERSION
ARG HADOOP_VERSION

ENV HADOOP_VERSION=${HADOOP_VERSION:-3.3.5}
ENV HIVE_VERSION=${HIVE_VERSION:-3.1.3}

# 4. 下载安装hadoop
# base URL for downloads: the name of the tar file depends
# on the target platform (amd64/x86_64 vs. arm64/aarch64)
ENV HADOOP_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/apache/hadoop/common/hadoop_$HADOOP_VERSION
ENV HADOOP_ASC_BASE_URL=https://www.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION

# 4.1 下载
RUN set -x \
    && ARCH=$(uname -m) \
    && ARCH=$(if test "$ARCH" = "x86_64"; then echo ""; else echo "-$ARCH"; fi) \
    && HADOOP_URL="$HADOOP_BASE_URL/hadoop-$HADOOP_VERSION$ARCH.tar.gz" \
    && HADOOP_ASC_URL="$HADOOP_ASC_BASE_URL/hadoop-$HADOOP_VERSION$ARCH.tar.gz.asc" \ 
    && curl -fSL "$HADOOP_URL" -o /tmp/hadoop.tar.gz \
    && curl -fSL "$HADOOP_ASC_URL" -o /tmp/hadoop.tar.gz.asc \
    && gpg --verify /tmp/hadoop.tar.gz.asc \
    && tar -zxvf /tmp/hadoop.tar.gz -C /opt/ \
    && rm /tmp/hadoop.tar.gz* 

# 4.2 hadoop的配置文件软连接到
RUN ln -s /opt/hadoop-$HADOOP_VERSION/etc/hadoop /etc/hadoop
RUN ln -e /opt/hadoop-$HADOOP_VERSION /opt/hadoop
RUN mkdir /opt/hadoop-$HADOOP_VERSION/logs
RUN mkdir /data/hadoop

# 4.3 HADOOP的环境变量 及 数据文件路径在entrypoint.sh中创建,是在创建了容器之后获取hostname来得到
ENV HADOOP_HOME=/opt/hadoop-$HADOOP_VERSION
ENV HADOOP_CONF_DIR=/etc/hadoop
ENV HADOOP_DATA_DIR=/data/hadoop

# 5. 下载安装 hive
ENV HIVE_HOME=/opt/hive-$HIVE_VERSION
ENV HIVE_URL=https://mirrors.tuna.tsinghua.edu.cn/apache/hive/hive-$HIVE_VERSION/apache-hive-$HIVE_VERSION-bin.tar.gz

RUN set -x \
    && curl -fSL "$HIVE_URL" -o /tmp/hive.tar.gz \
    && tar -zxvf /tmp/hive.tar.gz -C /opt/ \
    && mv /opt/apache-hive-$HIVE_VERSION-bin /opt/hive-$HIVE_VERSION \
    && rm /tmp/hive.tar.gz

# hive文件管理
RUN ln -s /opt/hadoop-$HADOOP_VERSION/conf /etc/hive
RUN ln -e /opt/hive-$HIVE_VERSION /opt/hive

ADD conf/hive/hive-site.xml $HIVE_HOME/conf
ADD conf/hive/beeline-log4j2.properties $HIVE_HOME/conf
ADD conf/hive/hive-env.sh $HIVE_HOME/conf
ADD conf/hive/hive-exec-log4j2.properties $HIVE_HOME/conf
ADD conf/hive/hive-log4j2.properties $HIVE_HOME/conf
ADD conf/hive/ivysettings.xml $HIVE_HOME/conf
ADD conf/hive/llap-daemon-log4j2.properties $HIVE_HOME/conf


# 6. 运行环境变量
ENV JAVA_HOME=/usr/lib/jvm/default-java
# create the symlink "/usr/lib/jvm/default-java" in case
# it is not already there (cf. package "default-jre-headless")
RUN if ! test -d $JAVA_HOME; then \
      ln -sf $(readlink -f $(dirname $(readlink -f $(which java)))/..) $JAVA_HOME; \
    fi
ENV PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin/:$PATH

ADD entrypoint.sh  /entrypoint.sh
RUN chmod a+x /entrypoint.sh 

ENTRYPOINT [ "/entrypoint.sh" ]
