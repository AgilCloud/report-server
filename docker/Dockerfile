FROM tomcat:9.0-jdk21-temurin-noble

ARG RS_VERSION=6.1.2
ARG RS_BUILD=6123
ARG RS_ZIP=RS6.1.2-6123-2026-04-16-14-17-01-reportserver-ce.zip
ARG RS_SHA256

ENV RS_CONFIG_DIR=/opt/reportserver/config \
    RS_DATA_DIR=/var/lib/reportserver \
    RS_DDL_DIR=/opt/reportserver/ddl

# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl postgresql-client unzip; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    test -n "${RS_SHA256:-}"; \
    rs_url="https://sourceforge.net/projects/dw-rs/files/bin/RS6/${RS_ZIP}/download"; \
    curl -fsSL -o /tmp/reportserver.zip "$rs_url"; \
    printf '%s  /tmp/reportserver.zip\n' "${RS_SHA256}" > /tmp/reportserver.zip.sha256; \
    sha256sum -c /tmp/reportserver.zip.sha256; \
    mkdir -p /tmp/reportserver-dist; \
    unzip -q /tmp/reportserver.zip -d /tmp/reportserver-dist; \
    war_path="$(find /tmp/reportserver-dist -type f -name '*.war' -print -quit)"; \
    rm -rf "$CATALINA_HOME/webapps"/*; \
    if [ -n "$war_path" ]; then \
        cp "$war_path" "$CATALINA_HOME/webapps/ROOT.war"; \
    elif unzip -l /tmp/reportserver.zip 'WEB-INF/*' >/dev/null 2>&1; then \
        baseconfig_zip="$(find /tmp/reportserver-dist/pkg -type f -name 'baseconfig-*.zip' -print -quit)"; \
        mkdir -p /tmp/reportserver-baseconfig; \
        unzip -q "$baseconfig_zip" -d /tmp/reportserver-baseconfig; \
        sed -i 's/<createdpassword disabled="false">/<createdpassword disabled="true">/' /tmp/reportserver-baseconfig/etc/security/notifications.cf; \
        sed -i 's/<changedpassword disabled="false">/<changedpassword disabled="true">/' /tmp/reportserver-baseconfig/etc/security/notifications.cf; \
        rm -f "$baseconfig_zip"; \
        jar --create --file "$baseconfig_zip" -C /tmp/reportserver-baseconfig .; \
        rm -rf /tmp/reportserver-baseconfig; \
        jar --create --file "$CATALINA_HOME/webapps/ROOT.war" -C /tmp/reportserver-dist .; \
    else \
        echo "No WAR file or root WEB-INF directory found in ${RS_ZIP}" >&2; \
        exit 1; \
    fi; \
    mkdir -p "$RS_DDL_DIR"; \
    cp "/tmp/reportserver-dist/ddl/reportserver-RS${RS_VERSION}-${RS_BUILD}-schema-PostgreSQL_CREATE.sql" "$RS_DDL_DIR/postgresql-create.sql"; \
    rm -rf /tmp/reportserver.zip /tmp/reportserver.zip.sha256 /tmp/reportserver-dist

RUN set -eux; \
    groupadd --gid 10001 reportserver; \
    useradd --uid 10001 --gid 10001 --home-dir /var/lib/reportserver --shell /usr/sbin/nologin reportserver; \
    mkdir -p /opt/reportserver/config /var/lib/reportserver "$RS_DDL_DIR"; \
    chown -R reportserver:reportserver "$CATALINA_HOME" /opt/reportserver /var/lib/reportserver

COPY --chown=reportserver:reportserver docker/bin/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

USER reportserver

EXPOSE 8080

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["catalina.sh", "run"]
