#!/bin/sh
# docker-entrypoint.sh
# Punto de entrada genérico para contenedores basados en alpine:latest
# - Ejecuta tareas de inicialización (creación de dirs, chown, scripts .sh)
# - Carga .sql/.sql.gz desde /entrypoint.d cuando se arranca mysqld
# - Reenvía señales al proceso hijo
# - Ejecuta el comando proporcionado como PID 1

set -eu
# pipefail puede no estar disponible en todas las variantes de sh; intentar de forma segura
if command -v sh >/dev/null 2>&1 && printf '' | (set -o pipefail 2>/dev/null; true); then
    set -o pipefail
fi

log() {
    printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

# Crear y asignar permisos a rutas listadas en INIT_DIRS (separadas por :)
if [ "${INIT_DIRS:-}" != "" ]; then
    IFS=':'; for d in $INIT_DIRS; do
        if [ -n "$d" ]; then
            log "Creando directorio: $d"
            mkdir -p "$d"
            if [ "${INIT_OWNER:-}" != "" ]; then
                log "Asignando propietario ${INIT_OWNER} a $d"
                chown -R "$INIT_OWNER" "$d" || true
            fi
        fi
    done
    unset IFS
fi

# Ejecutar scripts de inicialización en /docker-entrypoint-init.d
init_dir="/docker-entrypoint-init.d"
if [ -d "$init_dir" ]; then
    log "Buscando scripts de inicialización en $init_dir"
    for f in "$init_dir"/*; do
        [ -e "$f" ] || continue
        case "$f" in
            *.sh)
                log "Ejecutando script: $f"
                # Ejecutar en subshell para aislar entorno
                /bin/sh "$f"
                ;;
            *)
                log "Ignorando archivo (extensión no soportada): $f"
                ;;
        esac
    done
fi

# Preparar para procesar /entrypoint.d (scripts y sql)
entry_dir="/entrypoint.d"
SQL_FILES=""
if [ -d "$entry_dir" ]; then
    log "Buscando scripts y sql en $entry_dir"
    for f in "$entry_dir"/*; do
        [ -e "$f" ] || continue
        case "$f" in
            *.sh)
                log "Ejecutando script de entrada: $f"
                /bin/sh "$f"
                ;;
            *.sql|*.sql.gz)
                log "Detectado SQL: $f"
                SQL_FILES="$SQL_FILES $f"
                ;;
            *)
                log "Ignorando archivo en entrypoint.d: $f"
                ;;
        esac
    done
fi

# Funciones para inicialización MySQL temporal
mysql_auth_args() {
    # Devuelve args (sin expansión) para mysql/mysqladmin según env
    if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
        printf '%s' "-uroot -p${MYSQL_ROOT_PASSWORD}"
    else
        # Si se permite contraseña vacía, invocar sin -p (cliente intentará sin password)
        printf '%s' "-uroot"
    fi
}

wait_for_mysql() {
    # espera hasta que mysqladmin ping responda o agota tiempo
    max=30
    i=0
    while [ "$i" -lt "$max" ]; do
        if mysqladmin ping $(mysql_auth_args) --silent >/dev/null 2>&1; then
            return 0
        fi
        i=$((i+1))
        sleep 1
    done
    return 1
}

run_sql_file() {
    f="$1"
    case "$f" in
        *.sql)
            log "Cargando SQL: $f"
            mysql $(mysql_auth_args) < "$f"
            ;;
        *.sql.gz)
            log "Cargando SQL comprimido: $f"
            gunzip -c "$f" | mysql $(mysql_auth_args)
            ;;
        *)
            log "Formato SQL no soportado: $f"
            ;;
    esac
}

# Manejo de señales: reenviar señales a proceso hijo
child=0
term_handler() {
    sig="$1"
    log "Entró señal $sig, reenviando a PID $child"
    if [ "$child" -ne 0 ]; then
        kill -"$sig" "$child" 2>/dev/null || true
    fi
}
trap 'term_handler TERM' TERM
trap 'term_handler INT' INT
trap 'term_handler QUIT' QUIT
trap 'term_handler HUP' HUP

# Si no se pasan argumentos, abrir shell interactivo
if [ "$#" -eq 0 ]; then
    set -- /bin/sh
fi

# Si se detectaron SQLs y el comando es mysqld, arrancar un servidor temporal para cargarlos
case "$1" in
    *mysqld*)
        if [ -n "${SQL_FILES}" ]; then
            log "Iniciando servidor MySQL temporal para cargar .sql desde $entry_dir"
            # Arrancar mysqld en background con skip-networking para inicializar
            # Añadimos --skip-networking para evitar aceptación de conexiones externas durante la carga
            "$@" --skip-networking >/dev/null 2>&1 &
            tmp_pid=$!
            # Esperar a que el servidor responda
            if wait_for_mysql; then
                log "Servidor MySQL temporal listo, ejecutando archivos SQL"
                for f in $SQL_FILES; do
                    run_sql_file "$f" || {
                        log "Error cargando $f"
                        # decida si debe abortar: aquí continuamos con los demás archivos
                    }
                done
                log "Carga de SQL completada, deteniendo servidor MySQL temporal (PID $tmp_pid)"
                kill "$tmp_pid" 2>/dev/null || true
                # esperar que termine
                wait "$tmp_pid" 2>/dev/null || true
            else
                log "Timeout esperando MySQL temporal. No se cargaron los SQL."
                kill "$tmp_pid" 2>/dev/null || true
                wait "$tmp_pid" 2>/dev/null || true
            fi
            # Liberar lista para evitar re-ejecución posterior
            SQL_FILES=""
        fi
        ;;
    *)
        # Si no es mysqld pero existen SQLs intentamos cargarlos si hay cliente mysql y servidor accesible
        if [ -n "${SQL_FILES}" ]; then
            if command -v mysql >/dev/null 2>&1; then
                log "Servidor no es mysqld: intentando cargar SQL si hay un servidor accesible"
                if wait_for_mysql; then
                    for f in $SQL_FILES; do
                        run_sql_file "$f" || log "Error cargando $f"
                    done
                else
                    log "No se pudo contactar MySQL para cargar SQLs."
                fi
            else
                log "Cliente mysql no disponible; no se pueden cargar los SQLs."
            fi
            SQL_FILES=""
        fi
        ;;
esac

# Ejecutar el comando como PID 1 y esperar, para poder reenviar señales
log "Ejecutando: $*"
# Exec en background para poder capturar PID y seguir manejando señales
"$@" &
child=$!
# Esperar al proceso hijo y propagar su código de salida
wait "$child"
exit_code=$?
log "Proceso hijo finalizó con código $exit_code"
exit "$exit_code"