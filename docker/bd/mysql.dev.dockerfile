FROM alpine:latest

ARG DB_PORT=${DB_PORT}

RUN apk --no-cache add mysql mysql-client && \
    (addgroup -S mysql || true) && \
    (adduser -S -G mysql mysql || true)

COPY ./docker/bd/conf/mysql.dev.cnf /etc/my.cnf
COPY ./docker/bd/sql/init.dev.sql /docker-entrypoint-initdb.d/

RUN chown -R mysql:mysql /var/lib/mysql /var/run/mysqld
RUN chown -R mysql:mysql /var/run/mysqld
RUN chmod 777 /var/run/mysqld

EXPOSE ${DB_PORT}

USER mysql

ENTRYPOINT ["/usr/bin/mariadbd", "--defaults-file=/etc/my.cnf"]