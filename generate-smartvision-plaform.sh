#!/bin/bash

##############################################
# 🚀 SmartVision Platform Generator - VERSION OPTIMISÉE
# Basée sur la configuration existante qui fonctionne
##############################################

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 🎨 Fonctions utilitaires
log() { echo -e "${BLUE}📦 $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }

to_camel_case() { echo "$1" | sed -r 's/(^|-)([a-z])/\U\2/g'; }
package_format() { echo "$1" | tr '-' '_'; }

# 🔗 Mapping Spring Cloud
declare -A SPRING_CLOUD_VERSIONS=(
  ["3.4.7"]="2024.0.1"
  ["3.3.0"]="2023.0.1"
  ["3.2.0"]="2023.0.0"
)

# Variables globales
PLATFORM_NAME="smartvision-platform"
GROUP_ID="net.smart.vision"
JAVA_VERSION="17"
SPRINGBOOT_VERSION="3.4.7"
INIT_CONFIG_REPO=false
FORCE=false
INIT_REPO_PATH="$HOME/smartvision-config-repo"
SPRINGCLOUD_VERSION=""

# Services avec ports
SERVICES=("config-server" "eureka-server" "api-gateway" "video-core" "video-analyzer" "video-storage")
declare -A SERVICE_PORTS=(
  ["config-server"]=8888
  ["eureka-server"]=8761
  ["api-gateway"]=8084
  ["video-core"]=8085
  ["video-analyzer"]=8082
  ["video-storage"]=8083
)

# 🎛️ Arguments
parse_arguments() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --platform-name) PLATFORM_NAME="$2"; shift ;;
      --group-id) GROUP_ID="$2"; shift ;;
      --java-version) JAVA_VERSION="$2"; shift ;;
      --springboot-version) SPRINGBOOT_VERSION="$2"; shift ;;
      --init-config-repo) INIT_CONFIG_REPO=true; INIT_REPO_PATH="$2"; shift ;;
      --force) FORCE=true ;;
      --help) show_usage ;;
      *) error "Argument inconnu $1"; exit 1 ;;
    esac
    shift
  done
}

# 📋 Aide
show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --platform-name NAME    Nom de la plateforme (défaut: $PLATFORM_NAME)
  --group-id ID           Group ID Maven (défaut: $GROUP_ID)
  --java-version VERSION  Version Java (défaut: $JAVA_VERSION)
  --springboot-version V  Version Spring Boot (défaut: $SPRINGBOOT_VERSION)
  --init-config-repo PATH Initialiser le dépôt de configuration
  --force                 Forcer la recréation de la plateforme
  --help                  Afficher cette aide

Exemples:
  $0 --platform-name my-platform --group-id com.example --java-version 17
  $0 --init-config-repo \$HOME/my-config-repo --force
EOF
  exit 0
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
  if [ -d "$PLATFORM_NAME" ] && [ "$FORCE" = false ]; then
    error "Le dossier $PLATFORM_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi

  if ! command -v java &> /dev/null; then
    error "Java n'est pas installé"
    exit 1
  fi
}

# Fonction pour créer la structure du projet
create_project_structure() {
  log "🚀 Génération de la plateforme $PLATFORM_NAME..."
  
  if [ "$FORCE" = true ] && [ -d "$PLATFORM_NAME" ]; then
    log "♻️ Écrasement du dossier existant..."
    rm -rf "$PLATFORM_NAME"
  fi
  
  mkdir -p "$PLATFORM_NAME"
  
  # Créer les fichiers de projet
  create_gitignore
  generate_project_files
  generate_docker_compose
}

# Fonction pour créer le .gitignore
create_gitignore() {
  cat > "$PLATFORM_NAME/.gitignore" <<EOF
# IDE
.idea/
*.iml
*.ipr
*.iws
.vscode/
.classpath
.project
.settings/
bin/
build/
target/

# Docker
docker-compose.override.yml

# Logs
*.log
logs/

# Autres
*.swp
*.swo
.DS_Store
.env
*.bak
*.tmp

# Configuration locale
/config-repo/
EOF
  success "Fichier .gitignore créé"
}

# 📂 Initialisation du dépôt de configuration
init_config_repo() {
  local repo_path="${1:-$INIT_REPO_PATH}"
  log "📂 Initialisation du dépôt de configuration: $repo_path"
  
  mkdir -p "$repo_path"
  
  if [[ -d "$repo_path/.git" ]]; then
    warn "Dépôt de configuration existe déjà: $repo_path"
    return
  fi
  
  cd "$repo_path" || exit 1
  git init
  
  # Fichiers de configuration de base
  for SERVICE in "${SERVICES[@]}"; do
    generate_config_repo_file "$SERVICE" "${SERVICE_PORTS[$SERVICE]}" "$repo_path"
  done
  
  git add .
  git config user.email "generator@smartvision"
  git config user.name "SmartVision Generator"
  git commit -m "Initial commit: Configuration des microservices"
  
  success "Dépôt de configuration initialisé: $repo_path"
  cd - > /dev/null
}

# 📄 Génération des fichiers de configuration pour le dépôt
generate_config_repo_file() {
  local SERVICE_NAME="$1"
  local SERVICE_PORT="$2"
  local REPO_PATH="$3"

  case "$SERVICE_NAME" in
    "config-server")
      cat > "$REPO_PATH/config-server.yml" <<EOF
server:
  port: 8888

spring:
  application:
    name: config-server
  cloud:
    config:
      server:
        git:
          uri: file:$REPO_PATH
          clone-on-start: true
          force-pull: true
          default-label: \${CONFIG_REPO_BRANCH:main}

logging:
  level:
    org.springframework.cloud: DEBUG
    com.netflix: DEBUG
EOF
      ;;

    "eureka-server")
      cat > "$REPO_PATH/eureka-server.yml" <<EOF
server:
  port: 8761

eureka:
  client:
    service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}
    register-with-eureka: false
    fetch-registry: false

logging:
  level:
    org.springframework.cloud: DEBUG
    com.netflix: DEBUG
EOF
      ;;

    *)
      # Services génériques
      cat > "$REPO_PATH/$SERVICE_NAME.yml" <<EOF
server:
  port: $SERVICE_PORT

spring:
  application:
    name: $SERVICE_NAME
  cache:
    type: caffeine

eureka:
  client:
    register-with-eureka: true
    fetch-registry: true
    service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}

logging:
  level:
    org.springframework.cloud: DEBUG
    com.netflix: DEBUG

management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      enabled: true
    refresh:
      enabled: true
    loggers:
      enabled: true
EOF
      ;;
  esac
}

# 📂 Création d'un microservice
create_service() {
  local SERVICE_NAME="$1"
  local CAMEL_CASE_NAME=$(to_camel_case "$SERVICE_NAME")
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  local SERVICE_DIR="$PLATFORM_NAME/$SERVICE_NAME"

  log "Création du service: $SERVICE_NAME"

  if [[ "$FORCE" == false && -d "$SERVICE_DIR" ]]; then
    warn "Service $SERVICE_NAME existe déjà. Utilisez --force pour écraser."
    return
  fi

  if [[ "$FORCE" == true && -d "$SERVICE_DIR" ]]; then
    rm -rf "$SERVICE_DIR"
  fi

  mkdir -p "$SERVICE_DIR/src/main/java" "$SERVICE_DIR/src/main/resources"
  mkdir -p "$SERVICE_DIR/src/test/java" "$SERVICE_DIR/src/test/resources"

  # Déterminer les dépendances spécifiques
  local DEPENDENCIES=""
  local IMPORTS=""
  local ANNOTATION="@SpringBootApplication"
  local BOOTSTRAP_DEPENDENCY=""
  local VALIDATION_DEPENDENCY="<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>"
  local CACHE_DEPENDENCY="<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-cache</artifactId>
    </dependency>
    <dependency>
      <groupId>com.github.ben-manes.caffeine</groupId>
      <artifactId>caffeine</artifactId>
    </dependency>"

  case "$SERVICE_NAME" in
    "config-server")
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-config-server</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.config.server.EnableConfigServer;"
      ANNOTATION='@EnableConfigServer
@SpringBootApplication'
      # Config Server n'a pas besoin de bootstrap
      ;;

    "eureka-server")
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;"
      ANNOTATION='@EnableEurekaServer
@SpringBootApplication'
      BOOTSTRAP_DEPENDENCY="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-bootstrap</artifactId>
    </dependency>"
      ;;

    "api-gateway")
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-gateway</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.client.discovery.EnableDiscoveryClient;"
      ANNOTATION='@EnableDiscoveryClient
@SpringBootApplication'
      BOOTSTRAP_DEPENDENCY="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-bootstrap</artifactId>
    </dependency>"
      ;;

    *)
      # Services vidéo
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.client.discovery.EnableDiscoveryClient;"
      ANNOTATION='@EnableDiscoveryClient
@SpringBootApplication'
      BOOTSTRAP_DEPENDENCY="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-bootstrap</artifactId>
    </dependency>"
      ;;
  esac

  # pom.xml
  cat > "$SERVICE_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>$SPRINGBOOT_VERSION</version>
  </parent>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$SERVICE_NAME</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <properties>
    <java.version>$JAVA_VERSION</java.version>
    <spring-cloud.version>$SPRINGCLOUD_VERSION</spring-cloud.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    $DEPENDENCIES
    $BOOTSTRAP_DEPENDENCY
    $VALIDATION_DEPENDENCY
    $CACHE_DEPENDENCY
    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <optional>true</optional>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-dependencies</artifactId>
        <version>\${spring-cloud.version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
    </plugins>
  </build>
</project>
EOF

  # Application.java
  local PACKAGE_DIR=$(echo "$GROUP_ID" | sed 's/\./\//g')/$PACKAGE_SAFE
  mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR"

  cat > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/${CAMEL_CASE_NAME}Application.java" <<EOF
package $GROUP_ID.$PACKAGE_SAFE;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
$IMPORTS
import org.springframework.context.annotation.Profile;

@Profile("!test")
$ANNOTATION
public class ${CAMEL_CASE_NAME}Application {
    public static void main(String[] args) {
        SpringApplication.run(${CAMEL_CASE_NAME}Application.class, args);
    }
}
EOF

  # Fichiers de configuration
  generate_resource_files "$SERVICE_NAME" "$SERVICE_DIR" "${SERVICE_PORTS[$SERVICE_NAME]}"

  # Tests unitaires
  generate_unit_tests "$SERVICE_NAME" "$SERVICE_DIR" "$CAMEL_CASE_NAME" "$PACKAGE_SAFE"

  # Dockerfile
  cat > "$SERVICE_DIR/Dockerfile" <<EOF
FROM eclipse-temurin:$JAVA_VERSION-jdk-jammy
VOLUME /tmp
COPY "target/$SERVICE_NAME-0.0.1-SNAPSHOT.jar" app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
EOF

  success "Service $SERVICE_NAME créé"
}

# 📄 Génération des fichiers de ressources
generate_resource_files() {
  local SERVICE_NAME="$1"
  local SERVICE_DIR="$2"
  local SERVICE_PORT="$3"

  if [[ "$SERVICE_NAME" == "config-server" ]]; then
    # Config Server - application.yml seulement
    cat > "$SERVICE_DIR/src/main/resources/application.yml" <<EOF
server:
  port: $SERVICE_PORT
spring:
  application:
    name: config-server
  cloud:
    config:
      server:
        git:
          uri: file:\${HOME}/smartvision-config-repo
          clone-on-start: true
          force-pull: true
          default-label: \${CONFIG_REPO_BRANCH:main}

logging:
  level:
    org.springframework.cloud: DEBUG
    com.netflix: DEBUG
EOF

    # application-test.yml pour les tests
    cat > "$SERVICE_DIR/src/test/resources/application-test.yml" <<EOF
spring:
  cloud:
    config:
      enabled: false
eureka:
  client:
    enabled: false
EOF

  else
    # Services clients - bootstrap.yml pour la config
    cat > "$SERVICE_DIR/src/main/resources/bootstrap.yml" <<EOF
spring:
  application:
    name: $SERVICE_NAME
  cloud:
    config:
      uri: \${CONFIG_URI:http://localhost:8888}
      fail-fast: true
EOF

    # bootstrap-test.yml pour désactiver config server pendant les tests
    cat > "$SERVICE_DIR/src/test/resources/bootstrap-test.yml" <<EOF
spring:
  cloud:
    config:
      enabled: false
eureka:
  client:
    enabled: false
EOF

    # application-test.yml pour les tests
    cat > "$SERVICE_DIR/src/test/resources/application-test.yml" <<EOF
# Configuration de test générique
EOF
  fi
}

# 🧪 Génération des tests unitaires
generate_unit_tests() {
  local SERVICE_NAME="$1"
  local SERVICE_DIR="$2"
  local CAMEL_CASE_NAME="$3"
  local PACKAGE_SAFE="$4"
  local PACKAGE_DIR=$(echo "$GROUP_ID" | sed 's/\./\//g')/$PACKAGE_SAFE

  mkdir -p "$SERVICE_DIR/src/test/java/$PACKAGE_DIR"

  cat > "$SERVICE_DIR/src/test/java/$PACKAGE_DIR/${CAMEL_CASE_NAME}ApplicationTests.java" <<EOF
package $GROUP_ID.$PACKAGE_SAFE;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ${CAMEL_CASE_NAME}ApplicationTests {
    @Test
    void contextLoads() {}
}
EOF
}

# 🐳 Génération du docker-compose.yml
generate_docker_compose() {
  cat > "$PLATFORM_NAME/docker-compose.yml" <<EOF
version: '3.8'
services:
  mongodb:
    image: mongo:4.4
    container_name: mongodb
    ports:
      - "27017:27017"
    healthcheck:
      test: ["CMD", "mongo", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5

  config-server:
    build: ./config-server
    container_name: ${PLATFORM_NAME}-config-server
    ports:
      - "8888:8888"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8888/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - smartvision-net
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    environment:
      - HOME=${HOME}
      - CONFIG_REPO_BRANCH=\${CONFIG_REPO_BRANCH:-main}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}

  eureka-server:
    build: ./eureka-server
    hostname: eureka-server
    container_name: ${PLATFORM_NAME}-eureka-server
    ports:
      - "8761:8761"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8761/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    networks:
      - smartvision-net
    environment:
      - HOME=${HOME}
      - EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE=\${EUREKA_DEFAULTZONE:-http://eureka-server:8761/eureka/}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}
    depends_on:
      - config-server
EOF

  # Ajouter les autres services
  for SERVICE in "api-gateway" "video-core" "video-analyzer" "video-storage"; do
    PORT=${SERVICE_PORTS[$SERVICE]}
    cat >> "$PLATFORM_NAME/docker-compose.yml" <<EOF

  $SERVICE:
    build: ./$SERVICE
    container_name: ${PLATFORM_NAME}-$SERVICE
    ports:
      - "$PORT:$PORT"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$PORT/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - smartvision-net
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    environment:
      - HOME=${HOME}
      - EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE=\${EUREKA_DEFAULTZONE:-http://eureka-server:8761/eureka/}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}
    depends_on:
      - config-server
      - eureka-server
EOF
  done

  cat >> "$PLATFORM_NAME/docker-compose.yml" <<EOF

networks:
  smartvision-net:
    driver: bridge
EOF
}

# 📋 Génération des fichiers de projet
generate_project_files() {
  # .env.example
  cat > "$PLATFORM_NAME/.env.example" <<EOF
# Configuration Docker Compose
CONFIG_REPO_BRANCH=main
SPRING_PROFILES_ACTIVE=docker
EOF

  # README.md
  cat > "$PLATFORM_NAME/README.md" <<EOF
# $PLATFORM_NAME

Plateforme microservices SmartVision

## Services et Ports

| Service | Port |
|---------|------|
EOF

  for SERVICE in "${SERVICES[@]}"; do
    echo "| $SERVICE | ${SERVICE_PORTS[$SERVICE]} |" >> "$PLATFORM_NAME/README.md"
  done

  cat >> "$PLATFORM_NAME/README.md" <<EOF

## Démarrage

1. Copier le fichier d'environnement: \`cp .env.example .env\`
2. Construire les images: \`docker-compose build\`
3. Démarrer les services: \`docker-compose up -d\`

## Tests

\`\`\`bash
# Lancer les tests avec le profil test
mvn test -Dspring.profiles.active=test
\`\`\`
EOF
}

# 🎯 Fonction principale
main() {
  log "Démarrage de la génération de la plateforme..."
  parse_arguments "$@"
  
  SPRINGCLOUD_VERSION=${SPRING_CLOUD_VERSIONS[$SPRINGBOOT_VERSION]}
  if [ -z "$SPRINGCLOUD_VERSION" ]; then
    error "Version Spring Cloud non trouvée pour Spring Boot $SPRINGBOOT_VERSION"
    exit 1
  fi
  
  check_prerequisites
  create_project_structure
  
  for SERVICE in "${SERVICES[@]}"; do
    create_service "$SERVICE"
  done
  
  success "Plateforme $PLATFORM_NAME générée avec succès!"
  
  if [ "$INIT_CONFIG_REPO" = true ]; then
    init_config_repo "$INIT_REPO_PATH"
  fi
}

main "$@"
