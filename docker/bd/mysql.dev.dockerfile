FROM alpine:latest

# Variables de entorno configurables
ARG DB_PORT=${DB_PORT} \
    DB_USER=${DB_USER} \
    DB_PASS=${DB_PASS} \
    DB_ROOT_PASS=${DB_ROOT_PASS} \
    DB_NAME=${DB_NAME} \
    DB_DATADIR=${DB_DATADIR}


ENV DB_PORT=${DB_PORT} \
    DB_DATADIR=${DB_DATADIR} \
    DB_ROOT_PASS=${DB_ROOT_PASS} \
    DB_DATABASE=${DB_NAME} \
    DB_USER=${DB_USER} \
    DB_PASS=${DB_PASS}

# Instalar mariadb y cliente
RUN apk update && \
    apk add --no-cache mariadb mariadb-client mariadb-server-utils && \
    addgroup -S ${DB_USER} && \
    adduser -S ${DB_USER} -G ${DB_USER} && \
    mkdir -p ${DB_DATADIR} /run/mysqld && \
    chown -R ${DB_USER}:${DB_USER} ${DB_DATADIR} /run/mysqld && \
    echo "[mysqld] \n \
    datadir=${DB_DATADIR} \n \
    socket=${DB_DATADIR}/mysql.sock \n \
    user=${DB_USER} \n \
    bind-address=0.0.0.0" > /etc/my.cnf && \
    rm -rf /var/cache/apk/* /tmp/* && \
    mariadb-install-db --user=${DB_USER} --datadir=${DB_DATADIR}


# Exponer puerto
EXPOSE ${DB_PORT}

# Usuario no root
USER ${DB_USER}

# Entrypoint y comando por defecto
ENTRYPOINT [ "mariadbd","--datadir=/var/lib/mysql", "--socket=/run/mysqld/mysqld.sock"]

