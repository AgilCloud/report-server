SHELL := /bin/sh

COMPOSE ?= docker compose
ENV_FILE ?= .env
ENV_EXAMPLE ?= .env.example
BACKUP_DIR ?= backups
PROJECT_VOLUME_PREFIX ?= report-server

.PHONY: help env env-force config build up down restart ps logs logs-db logs-app health backup-db backup-data reset-volumes clean

help:
	@printf '%s\n' 'Alvos disponíveis:'
	@printf '%s\n' '  make env           Cria .env a partir de .env.example e gera senha local do banco se faltar'
	@printf '%s\n' '  make env-force     Recria .env a partir de .env.example e gera uma nova senha local do banco'
	@printf '%s\n' '  make config        Valida a configuração do Docker Compose'
	@printf '%s\n' '  make build         Constrói a imagem do ReportServer'
	@printf '%s\n' '  make up            Inicia a stack em background'
	@printf '%s\n' '  make down          Para a stack sem remover volumes'
	@printf '%s\n' '  make restart       Reinicia o serviço ReportServer'
	@printf '%s\n' '  make ps            Mostra o status dos serviços'
	@printf '%s\n' '  make logs          Acompanha logs de todos os serviços'
	@printf '%s\n' '  make logs-app      Acompanha logs do ReportServer'
	@printf '%s\n' '  make logs-db       Acompanha logs do PostgreSQL'
	@printf '%s\n' '  make health        Verifica o endpoint HTTP do ReportServer'
	@printf '%s\n' '  make backup-db     Exporta o PostgreSQL para backups/reportserver.sql'
	@printf '%s\n' '  make backup-data   Arquiva o volume reportserver_data'
	@printf '%s\n' '  make reset-volumes Apaga containers e volumes; requer CONFIRM=delete'

env:
	@if [ -f "$(ENV_FILE)" ]; then \
		printf '%s\n' "$(ENV_FILE) já existe; mantendo sem alterações."; \
		printf '%s\n' "Use 'make env-force' para recriá-lo."; \
	else \
		$(MAKE) env-force; \
	fi

env-force:
	@if [ ! -f "$(ENV_EXAMPLE)" ]; then \
		printf '%s\n' "$(ENV_EXAMPLE) não encontrado" >&2; \
		exit 1; \
	fi
	@umask 077; cp "$(ENV_EXAMPLE)" "$(ENV_FILE)"
	@password="$$( \
		if command -v openssl >/dev/null 2>&1; then \
			openssl rand -base64 32 | tr -d '\n'; \
		else \
			LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32; \
		fi \
	)"; \
	tmp_file="$$(mktemp)"; \
	sed "s|^RS_DB_PASSWORD=.*|RS_DB_PASSWORD=$$password|" "$(ENV_FILE)" > "$$tmp_file"; \
	cat "$$tmp_file" > "$(ENV_FILE)"; \
	rm -f "$$tmp_file"; \
	printf '%s\n' "$(ENV_FILE) criado com RS_DB_PASSWORD gerado."

config:
	$(COMPOSE) config

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart reportserver

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f

logs-app:
	$(COMPOSE) logs -f reportserver

logs-db:
	$(COMPOSE) logs -f db

health:
	curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$${REPORTSERVER_HTTP_PORT:-8080}/

backup-db:
	mkdir -p "$(BACKUP_DIR)"
	$(COMPOSE) exec db pg_dump -U reportserver reportserver > "$(BACKUP_DIR)/reportserver.sql"

backup-data:
	mkdir -p "$(BACKUP_DIR)"
	docker run --rm \
		-v "$(PROJECT_VOLUME_PREFIX)_reportserver_data:/data:ro" \
		-v "$$(pwd)/$(BACKUP_DIR):/backup" \
		alpine tar -czf /backup/reportserver-data.tar.gz -C /data .

reset-volumes:
	@if [ "$(CONFIRM)" != "delete" ]; then \
		printf '%s\n' "Recusando apagar volumes. Rode novamente com CONFIRM=delete."; \
		exit 1; \
	fi
	$(COMPOSE) down --volumes --remove-orphans

clean:
	$(COMPOSE) down --remove-orphans
