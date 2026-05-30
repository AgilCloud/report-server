# Docker para ReportServer CE

Empacotamento Docker/Compose para o ReportServer Community Edition 6.1.2 build 6123.

Este repositório cria uma imagem local do ReportServer CE, executa a aplicação com Docker Compose e documenta o contrato operacional de configuração, persistência, secrets e obrigações da licença AGPL.

## Requisitos

- Docker Engine com BuildKit habilitado
- Docker Compose v2
- Shell com ferramentas padrão de checksum, como `sha256sum` ou `shasum -a 256`
- Acesso à rede durante o build da imagem para baixar a distribuição do ReportServer CE, a menos que o Dockerfile seja ajustado futuramente para usar um artefato local

O ReportServer CE 6.1.2 build 6123 roda sobre Tomcat 9 e JDK 21. O Tomcat 9 é intencional porque o ReportServer CE 6.1.2 usa as APIs Java EE `javax.*`; Tomcat 10+ migrou para as APIs Jakarta `jakarta.*` e não é um runtime compatível direto. O JDK 21 é usado porque o arquivo 6.1.2 contém classes compiladas para Java 20+. O entrypoint adiciona a abertura extra de módulo Java necessária para a inicialização do file server do ReportServer em JDKs modernos.

## Configuração

Copie `.env.example` para `.env` antes de usar o Compose:

```sh
cp .env.example .env
```

Defina `RS_SHA256` com o checksum SHA-256 do arquivo upstream exato usado no build da imagem. Para `RS6.1.2-6123-2026-04-16-14-17-01-reportserver-ce.zip`, o checksum fixado é:

```env
RS_SHA256=9c2518b737cf614fc1fb420dd34402b8c8628a87912f5442c8f7509da7113a63
```

Recalcule e atualize esse valor sempre que o arquivo upstream mudar.

### Variáveis Principais

| Variável | Finalidade |
| --- | --- |
| `RS_VERSION` | Argumento de build com a versão do ReportServer CE, atualmente `6.1.2`. |
| `RS_BUILD` | Argumento de build com o número do build do ReportServer CE, atualmente `6123`. |
| `RS_ZIP` | Nome do arquivo upstream do ReportServer CE. |
| `RS_SHA256` | Checksum SHA-256 do arquivo de distribuição upstream. |
| `TZ` | Fuso horário dos containers. |
| `JAVA_XMS` | Heap inicial da JVM passado ao Tomcat. |
| `JAVA_XMX` | Heap máximo da JVM passado ao Tomcat. |
| `RS_BASE_URL` | URL pública base passada ao ReportServer como `rs.baseurl`. |
| `RS_DB_TYPE` | Tipo de banco. O entrypoint atualmente suporta PostgreSQL. |
| `RS_DB_HOST` | Hostname do banco, normalmente o nome do serviço Compose, como `db`. |
| `RS_DB_PORT` | Porta do banco. |
| `RS_DB_NAME` | Nome do banco do ReportServer. |
| `RS_DB_USER` | Usuário do banco do ReportServer. |
| `RS_DB_PASSWORD` | Senha do banco do ReportServer para desenvolvimento local simples. |
| `RS_DB_PASSWORD_FILE` | Caminho do arquivo que contém a senha do banco. Preferido para secrets. |
| `RS_CONFIG_DIR` | Diretório de configuração do ReportServer no container. |
| `RS_DATA_DIR` | Diretório de dados do ReportServer no container. |
| `RS_DB_INIT_SCHEMA` | Importa o DDL base PostgreSQL empacotado quando `public.rs_schemainfo` não existe. Padrão: `true`. |
| `RS_DB_CONNECT_TIMEOUT` | Segundos para aguardar o PostgreSQL antes de iniciar o Tomcat. Padrão: `120`. |
| `POSTGRES_DB` | Nome opcional do banco PostgreSQL incluído no Compose. |
| `POSTGRES_USER` | Usuário opcional do PostgreSQL incluído no Compose. |
| `POSTGRES_PASSWORD` | Senha opcional do PostgreSQL incluído no Compose para desenvolvimento local simples. |
| `POSTGRES_PASSWORD_FILE` | Caminho do arquivo que contém a senha do PostgreSQL. A stack Compose usa o mesmo secret file do ReportServer por padrão. |
| `REPORTSERVER_HTTP_PORT` | Porta do host mapeada para o HTTP do Tomcat. |

### Arquivos de Secret

Prefira variáveis `*_FILE` para senhas e outros secrets:

```env
RS_DB_PASSWORD_FILE=/run/secrets/reportserver_db_password
POSTGRES_PASSWORD_FILE=/run/secrets/reportserver_db_password
```

Esta stack Compose cria o secret `reportserver_db_password` a partir da variável local `RS_DB_PASSWORD` e monta esse secret em `/run/secrets/reportserver_db_password` para os dois serviços. Mantenha `.env` fora do Git e fora do contexto de build Docker.

Se uma variável direta e sua contraparte `*_FILE` estiverem definidas ao mesmo tempo, o entrypoint em runtime prefere o valor do arquivo. Se uma variável `*_FILE` apontar para um arquivo ilegível, a inicialização falha em vez de fazer fallback silencioso.

## Build Local

Construa a imagem com Compose:

```sh
set -a
. ./.env
set +a
docker compose build
```

Ou passe o checksum diretamente ao construir a imagem manualmente:

```sh
docker build \
  --build-arg RS_VERSION=6.1.2 \
  --build-arg RS_BUILD=6123 \
  --build-arg RS_SHA256="$RS_SHA256" \
  -f docker/Dockerfile \
  -t reportserver-ce:6.1.2-6123 .
```

O build deve falhar se o arquivo baixado não corresponder a `RS_SHA256`.

## Execução com Compose

Crie `.env`, configure os secrets e inicie a stack. O Compose passa o build arg `RS_SHA256` fixado, e o `.env` pode sobrescrevê-lo quando o arquivo upstream mudar.

```sh
docker compose up -d
docker compose logs -f
```

Acesse o ReportServer em:

```text
http://localhost:${REPORTSERVER_HTTP_PORT:-8080}/
```

Este repositório não inclui nem pressupõe um proxy reverso embutido. Se TLS, roteamento por host, SSO ou acesso externo forem necessários, trate esses pontos na infraestrutura fora desta imagem de aplicação.

## Volumes

Use volumes nomeados para persistência da aplicação e do banco:

- `reportserver_config` armazena configurações geradas do ReportServer, como `persistence.properties`.
- `reportserver_data` armazena estado runtime do ReportServer que deve sobreviver à troca de containers.
- `postgres_data` armazena o diretório de dados do PostgreSQL incluído no Compose.

Não armazene estado persistente na camada gravável do container. Trate containers como substituíveis e volumes como a fronteira durável.

## Backup e Restauração

Faça backup do banco antes de upgrades, mudanças de imagem ou migrações:

```sh
mkdir -p backups
docker compose exec db pg_dump -U reportserver reportserver > backups/reportserver.sql
```

Faça backup dos volumes nomeados quando eles contiverem arquivos gerenciados pelo ReportServer ou configuração externalizada:

```sh
docker run --rm \
  -v "report-server_reportserver_data:/data:ro" \
  -v "$PWD/backups:/backup" \
  alpine tar -czf /backup/reportserver-data.tar.gz -C /data .
```

Se `COMPOSE_PROJECT_NAME` estiver definido, substitua o prefixo de volume `report-server_` pelo nome do projeto.

Restaure em uma stack parada ou em volumes novos:

```sh
docker compose down
docker compose up -d db
docker compose exec -T db psql -U reportserver reportserver < backups/reportserver.sql
```

Para restaurar volumes, crie ou limpe o volume de destino primeiro e depois extraia o arquivo nele. Valide procedimentos de restauração em um ambiente não produtivo antes de depender deles.

## Troubleshooting

- Verifique logs de inicialização com `docker compose logs -f reportserver` e logs do banco com `docker compose logs -f db`.
- Se o Tomcat iniciar, mas a aplicação falhar, confirme que a imagem usa Tomcat 9 e JDK 21.
- Se o build falhar na validação de checksum, recalcule o SHA-256 a partir do arquivo upstream e atualize `RS_SHA256`.
- Se a autenticação no banco falhar, confirme se `RS_DB_PASSWORD_FILE` ou `RS_DB_PASSWORD` está sendo usado pelo container em execução.
- Se o banco estiver inacessível, verifique `RS_DB_HOST`, `RS_DB_PORT`, nomes de serviços Compose e associação à rede.
- Se a inicialização falhar com `relation "public.rs_revision" does not exist`, reconstrua a imagem e inicie novamente para que o entrypoint importe o DDL base PostgreSQL empacotado. Para um banco de teste que já ficou parcialmente inicializado, `docker compose down --volumes` oferece uma nova tentativa limpa, mas apaga os dados.
- Se a troca da senha inicial do `root` falhar com `No default Email - SMTP server datasink configured`, reconstrua a imagem. A imagem Docker desativa emails de notificação de senha criada/alterada na configuração base empacotada, então trocas de senha não exigem SMTP. Volumes existentes criados antes dessa correção podem ser ajustados pela UI do ReportServer editando `/fileserver/etc/security/notifications.cf` e definindo `createdpassword` e `changedpassword` como `disabled="true"`.
- Se dados desaparecerem após recriação, confirme que o Compose está usando volumes nomeados em vez de caminhos anônimos ou locais ao container.
- Se login ou inicialização se comportarem de forma inesperada, verifique se o banco foi inicializado uma única vez e não foi reutilizado acidentalmente entre experimentos incompatíveis.

## Docker Hub, Secrets e Tags

Publique imagens somente após validação de checksum e CI limpo. Tags recomendadas:

- `6.1.2-6123`
- `6.1.2`
- opcionalmente `latest`, apenas se a política do projeto disser que ela acompanha a imagem ReportServer CE mais nova suportada

Nunca grave secrets em camadas da imagem, labels, build args ou descrições no Docker Hub. Build args não são mecanismo de secret. Use variáveis de ambiente em runtime, `*_FILE`, Compose secrets ou armazenamentos de secret nativos da plataforma.

Ao publicar, inclua a versão do ReportServer CE, número do build, compatibilidade do runtime base, fonte do checksum e aviso AGPL nas release notes ou na documentação da imagem.

## AGPL

O ReportServer CE é licenciado sob a GNU Affero General Public License. Se você modificar o ReportServer ou distribuir/disponibilizar em rede uma versão modificada, entenda e cumpra as obrigações da AGPL sobre disponibilidade de código-fonte.

Para este empacotamento Docker, mantenha visíveis e auditáveis:

- Versão upstream e número do build do ReportServer CE.
- Quaisquer patches locais ou modificações no nível da imagem.
- Locais do código-fonte correspondente para componentes modificados cobertos pela AGPL.
- Avisos de licença e atribuição.
- Instruções necessárias para que usuários obtenham o código-fonte correspondente.

Este README é orientação operacional, não aconselhamento jurídico.
