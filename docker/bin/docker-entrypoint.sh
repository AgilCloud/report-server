#!/bin/sh
set -eu

file_env() {
	var_name="$1"
	file_var_name="${var_name}_FILE"
	default_value="${2:-}"

	eval var_value=\${$var_name:-}
	eval file_var_value=\${$file_var_name:-}

	if [ -n "$file_var_value" ] && [ -r "$file_var_value" ]; then
		cat "$file_var_value"
	elif [ -n "$file_var_value" ]; then
		echo "$file_var_name is set but $file_var_value is not readable" >&2
		exit 1
	elif [ -n "$var_value" ]; then
		printf '%s' "$var_value"
	else
		printf '%s' "$default_value"
	fi
}

append_prop() {
	prop_file="$1"
	prop_key="$2"
	prop_value="$3"

	printf '%s=%s\n' "$prop_key" "$prop_value" >> "$prop_file"
}

RS_CONFIG_DIR="${RS_CONFIG_DIR:-/opt/reportserver/config}"
RS_DATA_DIR="${RS_DATA_DIR:-/var/lib/reportserver}"
RS_DDL_DIR="${RS_DDL_DIR:-/opt/reportserver/ddl}"
RS_DB_INIT_SCHEMA="${RS_DB_INIT_SCHEMA:-true}"
RS_DB_CONNECT_TIMEOUT="${RS_DB_CONNECT_TIMEOUT:-120}"

RS_DB_TYPE="$(file_env RS_DB_TYPE postgresql)"
RS_DB_HOST="$(file_env RS_DB_HOST postgres)"
RS_DB_PORT="$(file_env RS_DB_PORT 5432)"
RS_DB_NAME="$(file_env RS_DB_NAME reportserver)"
RS_DB_USER="$(file_env RS_DB_USER reportserver)"
RS_DB_PASSWORD="$(file_env RS_DB_PASSWORD '')"
RS_BASE_URL="$(file_env RS_BASE_URL '')"

mkdir -p "$RS_CONFIG_DIR" "$RS_DATA_DIR"

persistence_file="$RS_CONFIG_DIR/persistence.properties"
tmp_persistence_file="${persistence_file}.$$"

case "$RS_DB_TYPE" in
	postgres|postgresql)
		hibernate_dialect="net.datenwerke.rs.utils.hibernate.PostgreSQLDialect"
		jdbc_driver="org.postgresql.Driver"
		jdbc_url="jdbc:postgresql://${RS_DB_HOST}:${RS_DB_PORT}/${RS_DB_NAME}"
		;;
	*)
		echo "Unsupported RS_DB_TYPE: $RS_DB_TYPE" >&2
		exit 1
		;;
esac

init_postgresql_schema() {
	ddl_file="$RS_DDL_DIR/postgresql-create.sql"

	if [ "$RS_DB_INIT_SCHEMA" != "true" ]; then
		return 0
	fi

	if [ ! -r "$ddl_file" ]; then
		echo "PostgreSQL schema initialization is enabled but $ddl_file is not readable" >&2
		exit 1
	fi

	export PGPASSWORD="$RS_DB_PASSWORD"

	attempt=1
	while ! psql -h "$RS_DB_HOST" -p "$RS_DB_PORT" -U "$RS_DB_USER" -d "$RS_DB_NAME" -v ON_ERROR_STOP=1 -Atc "select 1" >/dev/null 2>&1; do
		if [ "$attempt" -ge "$RS_DB_CONNECT_TIMEOUT" ]; then
			echo "Timed out waiting for PostgreSQL at ${RS_DB_HOST}:${RS_DB_PORT}/${RS_DB_NAME}" >&2
			exit 1
		fi
		attempt=$((attempt + 1))
		sleep 1
	done

	if psql -h "$RS_DB_HOST" -p "$RS_DB_PORT" -U "$RS_DB_USER" -d "$RS_DB_NAME" -v ON_ERROR_STOP=1 -Atc "select to_regclass('public.rs_schemainfo')" | grep -q '^rs_schemainfo$'; then
		return 0
	fi

	rs_table_count="$(psql -h "$RS_DB_HOST" -p "$RS_DB_PORT" -U "$RS_DB_USER" -d "$RS_DB_NAME" -v ON_ERROR_STOP=1 -Atc "select count(*) from information_schema.tables where table_schema = 'public' and lower(table_name) like 'rs_%'")"
	if [ "$rs_table_count" != "0" ]; then
		echo "ReportServer schema looks partially initialized but public.rs_schemainfo is missing; refusing to import base DDL automatically" >&2
		exit 1
	fi

	echo "Initializing ReportServer PostgreSQL base schema"
	psql -h "$RS_DB_HOST" -p "$RS_DB_PORT" -U "$RS_DB_USER" -d "$RS_DB_NAME" -v ON_ERROR_STOP=1 -f "$ddl_file"
}

if [ "$RS_DB_TYPE" = "postgres" ] || [ "$RS_DB_TYPE" = "postgresql" ]; then
	init_postgresql_schema
fi

: > "$tmp_persistence_file"
append_prop "$tmp_persistence_file" "hibernate.dialect" "$hibernate_dialect"
append_prop "$tmp_persistence_file" "hibernate.connection.driver_class" "$jdbc_driver"
append_prop "$tmp_persistence_file" "hibernate.connection.url" "$jdbc_url"
append_prop "$tmp_persistence_file" "hibernate.connection.username" "$RS_DB_USER"
append_prop "$tmp_persistence_file" "hibernate.connection.password" "$RS_DB_PASSWORD"
append_prop "$tmp_persistence_file" "hibernate.connection.provider_class" "org.hibernate.connection.C3P0ConnectionProvider"

mv "$tmp_persistence_file" "$persistence_file"
chmod 0600 "$persistence_file"

if [ -n "$RS_BASE_URL" ]; then
	JAVA_OPTS="${JAVA_OPTS:-} -Drs.baseurl=${RS_BASE_URL}"
fi

if [ -n "${JAVA_XMS:-}" ]; then
	JAVA_OPTS="${JAVA_OPTS:-} -Xms${JAVA_XMS}"
fi

if [ -n "${JAVA_XMX:-}" ]; then
	JAVA_OPTS="${JAVA_OPTS:-} -Xmx${JAVA_XMX}"
fi

JAVA_OPTS="${JAVA_OPTS:-} --add-opens=java.base/java.net=ALL-UNNAMED -Drs.configdir=${RS_CONFIG_DIR} -Drs.data.dir=${RS_DATA_DIR}"
export JAVA_OPTS

exec "$@"
