
CREATE DATABASE `hive` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

grant all PRIVILEGES on *.* to hive@'%';

flush privileges;