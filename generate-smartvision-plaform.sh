#!/bin/bash

# ============================================================
# Script : generate-smartvision-platform.sh
# Objectif : Générer une plateforme microservices Spring Boot Cloud
# Auteuer : Ahmadou DIALLO
# ============================================================

# Configuration par défaut
DEFAULT_PLATFORM_NAME="smartvision-platform"
DEFAULT_GROUP_ID="com.example"
DEFAULT_ARTIFACT_PREFIX="smartvision"
DEFAULT_SPRINGBOOT_VERSION="3.3.0"
DEFAULT_JAVA_VERSION="17"
DEFAULT_CONFIG_REPO_DIR="${HOME}/smartvision-config-repo"

# Variables globales
PLATFORM_NAME=""
GROUP_ID=""
ARTIFACT_PREFIX=""
SPRINGBOOT_VERSION=""
JAVA_VERSION=""
CONFIG_REPO_DIR=""
FORCE_OVERWRITE=false

# Liste des services
SERVICES=("eureka-server" "config-server" "api-gateway" "video-core" "video-analyzer" "video-storage")

# Ports associés
declare -A SERVICE_PORTS=(
  ["config-server"]=8888
  ["eureka-server"]=8761
  ["api-gateway"]=8084
  ["video-core"]=8081
  ["video-analyzer"]=8082
  ["video-storage"]=8083
)

# Correspondance Spring Boot -> Spring Cloud
declare -A SPRING_CLOUD_VERSIONS=(
  ["3.3.0"]="2023.0.1"
  ["3.2.0"]="2023.0.0"
  ["3.1.0"]="2022.0.3"
)

# Fonction pour convertir en CamelCase
to_camel_case() {
  echo "$1" | sed -r 's/(^|-)([a-z])/\u\2/g'
}

# Fonction pour afficher l'usage
usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -n, --name <name>         Nom de la plateforme (défaut: $DEFAULT_PLATFORM_NAME)"
  echo "  -g, --group-id <id>       Group ID Maven (défaut: $DEFAULT_GROUP_ID)"
  echo "  -a, --artifact-prefix <p> Préfixe pour les artifactId (défaut: $DEFAULT_ARTIFACT_PREFIX)"
  echo "  -b, --boot-version <v>    Version Spring Boot (défaut: $DEFAULT_SPRINGBOOT_VERSION)"
  echo "  -j, --java-version <v>    Version Java (défaut: $DEFAULT_JAVA_VERSION)"
  echo "  -c, --config-dir <dir>    Dossier de configuration (défaut: $DEFAULT_CONFIG_REPO_DIR)"
  echo "  -f, --force               Forcer l'écrasement si le dossier existe"
  echo "  -h, --help                Afficher cette aide"
  exit 1
}

# Fonction pour parser les arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--name)
        PLATFORM_NAME="$2"
        shift 2
        ;;
      -g|--group-id)
        GROUP_ID="$2"
        shift 2
        ;;
      -a|--artifact-prefix)
        ARTIFACT_PREFIX="$2"
        shift 2
        ;;
      -b|--boot-version)
        SPRINGBOOT_VERSION="$2"
        shift 2
        ;;
      -j|--java-version)
        JAVA_VERSION="$2"
        shift 2
        ;;
      -c|--config-dir)
        CONFIG_REPO_DIR="$2"
        shift 2
        ;;
      -f|--force)
        FORCE_OVERWRITE=true
        shift
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "Option inconnue: $1"
        usage
        ;;
    esac
  done
}

# Fonction pour initialiser les valeurs par défaut
init_defaults() {
  PLATFORM_NAME=${PLATFORM_NAME:-$DEFAULT_PLATFORM_NAME}
  GROUP_ID=${GROUP_ID:-$DEFAULT_GROUP_ID}
  ARTIFACT_PREFIX=${ARTIFACT_PREFIX:-$DEFAULT_ARTIFACT_PREFIX}
  SPRINGBOOT_VERSION=${SPRINGBOOT_VERSION:-$DEFAULT_SPRINGBOOT_VERSION}
  JAVA_VERSION=${JAVA_VERSION:-$DEFAULT_JAVA_VERSION}
  CONFIG_REPO_DIR=${CONFIG_REPO_DIR:-$DEFAULT_CONFIG_REPO_DIR}
  
  # Déterminer la version de Spring Cloud
  SPRINGCLOUD_VERSION=${SPRING_CLOUD_VERSIONS[$SPRINGBOOT_VERSION]}
  if [ -z "$SPRINGCLOUD_VERSION" ]; then
    echo "⚠️ Version Spring Cloud non trouvée pour Spring Boot $SPRINGBOOT_VERSION"
    echo "Versions supportées: ${!SPRING_CLOUD_VERSIONS[@]}"
    exit 1
  fi
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
  if [ -d "$PLATFORM_NAME" ] && [ "$FORCE_OVERWRITE" = false ]; then
    echo "❌ Le dossier $PLATFORM_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi

  if ! command -v java &> /dev/null; then
    echo "❌ Java n'est pas installé"
    exit 1
  fi

  if ! command -v docker &> /dev/null; then
    echo "⚠️ Docker n'est pas installé - certaines fonctionnalités ne fonctionneront pas"
  fi
}

# Fonction pour créer la structure du projet
create_project_structure() {
  echo "🚀 Génération de la plateforme $PLATFORM_NAME..."
  
  if [ "$FORCE_OVERWRITE" = true ] && [ -d "$PLATFORM_NAME" ]; then
    echo "♻️ Écrasement du dossier existant..."
    rm -rf "$PLATFORM_NAME"
  fi
  
  mkdir -p "$PLATFORM_NAME"
  cd "$PLATFORM_NAME" || exit 1
  
  # Créer le fichier .gitignore
  create_gitignore
  
  # Créer le dossier de configuration centralisée
  mkdir -p "$CONFIG_REPO_DIR"
  echo "📂 Dossier de configuration créé: $CONFIG_REPO_DIR"
}

# Fonction pour créer le .gitignore
create_gitignore() {
  cat > .gitignore <<EOF
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
  echo "📌 Fichier .gitignore créé"
}

# Formatte les noms de packages (remplace - par .)
format_package_name() {
  echo "$1" | tr '-' '.'
}

# Ajoute les dépendances communes au POM
add_common_dependencies() {
  local service_dir="$1"
  local pom_file="$service_dir/pom.xml"
  
  # Insertion après la balise <dependencies>
  sed -i '/<\/dependencies>/i \
    <dependency>\
      <groupId>org.projectlombok</groupId>\
      <artifactId>lombok</artifactId>\
      <version>1.18.32</version>\
      <scope>provided</scope>\
    </dependency>' "$pom_file"
}

# logging method: here logs are logged
init_logging() {
  # Dossier de logs dans le home directory

  LOG_DIR="${HOME}/smartvision-logs"  # Au lieu de /var/log/smartvision
  mkdir -p "$LOG_DIR"
  
  # Création du dossier si inexistant
  if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    echo "⚠️ Impossible de créer ${LOG_DIR}, utilisation de /tmp"
    LOG_DIR="/tmp/smartvision-logs"
    mkdir -p "$LOG_DIR"
  fi

  LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
  touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/dev/null"
  
  export LOG_DIR LOG_FILE
}

# Fonction pour générer un microservice
generate_microservice() {
  local SERVICE=$1
  local PORT=$2
  local ARTIFACT_ID="$ARTIFACT_PREFIX-$SERVICE"
  local CLASS_NAME=$(to_camel_case "$SERVICE")Application
  
  echo "📦 Création du microservice : $SERVICE (port $PORT)"
  
  mkdir -p "$SERVICE/src/main/java/${GROUP_ID//.//}/$SERVICE"
  mkdir -p "$SERVICE/src/main/resources"
  mkdir -p "$SERVICE/src/test/java/${GROUP_ID//.//}/$SERVICE"

  # Créer pom.xml
  create_pom_xml "$SERVICE" "$ARTIFACT_ID"
  
  add_common_dependencies "$SERVICE"
  
  # Créer fichiers de configuration
  create_config_files "$SERVICE" "$PORT"
  
  # Créer classe Main
  create_main_class "$SERVICE" "$CLASS_NAME"
  
  # Créer Dockerfile
  create_dockerfile "$SERVICE"
  
  # Créer test de base
  create_test_class "$SERVICE" "$CLASS_NAME"
  
  # Ajoutez cette ligne après la création des autres fichiers
  create_test_resources "$SERVICE"
}

# Fonction pour créer le pom.xml
create_pom_xml() {
  local SERVICE=$1
  local ARTIFACT_ID=$2
  
  cat > "$SERVICE/pom.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$ARTIFACT_ID</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>$SPRINGBOOT_VERSION</version>
  </parent>
  <dependencies>
    <!-- Dépendances communes -->
EOF

  # Ne pas ajouter web pour l'api-gateway
  if [ "$SERVICE" != "api-gateway" ]; then
    cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
EOF
  fi

  cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
EOF

  # Dépendances spécifiques
  if [ "$SERVICE" == "config-server" ]; then
    cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-config-server</artifactId>
    </dependency>
EOF
  else
    cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
EOF
    if [ "$SERVICE" == "eureka-server" ]; then
      cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
    </dependency>
EOF
    fi
    if [ "$SERVICE" == "api-gateway" ]; then
      cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-webflux</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-gateway</artifactId>
    </dependency>
EOF
    fi
    if [ "$SERVICE" == "video-analyzer" ]; then
      cat >> "$SERVICE/pom.xml" <<EOF
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-mongodb</artifactId>
    </dependency>
EOF
    fi
  fi

  # Dépendances de test
  cat >> "$SERVICE/pom.xml" <<EOF
    <!-- Test -->
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
        <version>$SPRINGCLOUD_VERSION</version>
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

  <properties>
    <java.version>$JAVA_VERSION</java.version>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
</project>
EOF
}

# Fonction pour créer les fichiers de configuration
create_config_files() {
  local SERVICE=$1
  local PORT=$2
  
  # application.yml ou bootstrap.yml
  if [ "$SERVICE" == "config-server" ]; then
    cat > "$SERVICE/src/main/resources/application.yml" <<EOF
server:
  port: $PORT

spring:
  application:
    name: config-server
  cloud:
    config:
      server:
        git:
          uri: file://$CONFIG_REPO_DIR
          clone-on-start: true
          force-pull: true

management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
EOF
  else
    cat > "$SERVICE/src/main/resources/bootstrap.yml" <<EOF
server:
  port: $PORT

spring:
  application:
    name: $SERVICE
  config:
    import:import: optional:configserver:${CONFIG_SERVER_URI:http://config-server:8888}
  cloud:
    config:
      uri: http://config-server:8888
      fail-fast: true
      retry:
        initial-interval: 1000
        max-interval: 2000
        multiplier: 1.5
        max-attempts: 3
    
eureka:
  client:
    serviceUrl:
      defaultZone: http://${PLATFORM_NAME}-eureka-server:8761/eureka/
  instance:
    prefer-ip-address: true

management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
EOF
    
    # Créer aussi un application.yml pour les configurations spécifiques
    if [ "$SERVICE" == "video-analyzer" ]; then
      cat > "$SERVICE/src/main/resources/application.yml" <<EOF
spring:
  data:
    mongodb:
      host: mongodb
      port: 27017
      database: video-analysis

video:
  processing:
    threads: 4
    timeout: 5000
EOF
    fi
  fi
}

create_test_resources() {
  local SERVICE=$1
  mkdir -p "$SERVICE/src/test/resources"
  
  # Configuration de base pour tous les tests
  cat > "$SERVICE/src/test/resources/application-test.yml" <<EOF
spring:
  cloud:
    config:
      enabled: false
      import-check:
        enabled: false

management:
  endpoints:
    web:
      exposure:
        include: "*"

logging:
  level:
    root: INFO
EOF

  # Configuration spécifique pour Eureka
  if [ "$SERVICE" == "eureka-server" ]; then
    cat >> "$SERVICE/src/test/resources/application-test.yml" <<EOF

eureka:
  client:
    register-with-eureka: false
    fetch-registry: false
EOF
  fi
  
  if [ "$SERVICE" == "video-analyszer" ]; then 
    cat >> "$SERVICE/src/test/resources/application-test.yml" <<EOF
spring:
  data:
    mongodb:
      host: mongodb
      port: 27017
      database: video-analyzer-test
      auto-index-creation: true
eureka:
  client:
    register-with-eureka: false
    fetch-registry: false

management:
  endpoints:
    web:
      exposure:
        include: "*"

logging:
  level:
    root: INFO
EOF
  fi
}

# Fonction pour créer la classe Main
create_main_class() {
  local SERVICE=$1
  local CLASS_NAME=$2
  local PACKAGE_NAME=$(format_package_name "$SERVICE")
  local PACKAGE_PATH="${GROUP_ID//.//}/$SERVICE"  # Garde la structure de dossier originale
  local MAIN_CLASS="$SERVICE/src/main/java/$PACKAGE_PATH/$CLASS_NAME.java"

  mkdir -p "$(dirname "$MAIN_CLASS")"

  {
    echo "package ${GROUP_ID}.${PACKAGE_NAME};"
    echo ""
    echo "import org.springframework.boot.SpringApplication;"
    echo "import org.springframework.boot.autoconfigure.SpringBootApplication;"
    echo "import lombok.extern.slf4j.Slf4j;"

    if [ "$SERVICE" == "eureka-server" ]; then
      echo "import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;"
    elif [ "$SERVICE" == "config-server" ]; then
      echo "import org.springframework.cloud.config.server.EnableConfigServer;"
    fi

    echo ""
    echo "@Slf4j"
    echo "@SpringBootApplication"
    
    if [ "$SERVICE" == "eureka-server" ]; then
      echo "@EnableEurekaServer"
    elif [ "$SERVICE" == "config-server" ]; then
      echo "@EnableConfigServer"
    fi

    echo "public class ${CLASS_NAME} {"
    echo "    public static void main(String[] args) {"
    echo "        log.info(\"Starting ${CLASS_NAME}...\");"
    echo "        SpringApplication.run(${CLASS_NAME}.class, args);"
    echo "    }"
    echo "}"
  } > "$MAIN_CLASS"
}


# Fonction pour créer le Dockerfile
create_dockerfile() {
  local SERVICE=$1
  
  # Cas particulier pour les services sans dépendance
    cat > "$SERVICE/Dockerfile" <<EOF
FROM eclipse-temurin:17-jdk-alpine
VOLUME /tmp
COPY target/smartvision-$SERVICE-0.0.1-SNAPSHOT.jar app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
EOF
}

# Fonction pour créer une classe de test
create_test_class() {
  local SERVICE=$1
  local CLASS_NAME=$2
  local PACKAGE_NAME=$(format_package_name "$SERVICE")
  local TEST_CLASS="$SERVICE/src/test/java/${GROUP_ID//.//}/$SERVICE/${CLASS_NAME}Test.java"

  mkdir -p "$(dirname "$TEST_CLASS")"

  cat > "$TEST_CLASS" <<EOF
package ${GROUP_ID}.${PACKAGE_NAME};

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ${CLASS_NAME}Test {

    @Test
    void contextLoads() {
        // Test que le contexte Spring se charge correctement
    }
}
EOF
}

# Fonction pour créer le docker-compose.yml
create_docker_compose() {
  echo "version: '3.8'
services:" > docker-compose.yml

  # Services applicatifs
  for SERVICE in "${SERVICES[@]}"; do
    local PORT=${SERVICE_PORTS[$SERVICE]}
    echo "  $SERVICE:
    build: ./$SERVICE
    container_name: $SERVICE
    ports:
      - \"$PORT:$PORT\"
    environment:
      - SPRING_PROFILES_ACTIVE=docker" >> docker-compose.yml
      
    # Configuration réseau
    if [ "$SERVICE" == "eureka-server" ]; then
      echo "    networks:
      - smartvision-net" >> docker-compose.yml
    fi
    
    # Dépendances
    if [ "$SERVICE" == "eureka-server" ]; then
      echo "    depends_on:
      - config-server
      - mongodb" >> docker-compose.yml
    elif [ "$SERVICE" != "config-server" ]; then
      echo "    depends_on:
      - eureka-server" >> docker-compose.yml
    fi
        	   
    # Dépendance spécifique pour video-analyzer
    if [ "$SERVICE" == "video-analyzer" ]; then
      echo "    depends_on:
      - mongodb" >> docker-compose.yml
    fi
  done

  # Services supplémentaires (MongoDB)
  echo "  mongodb:
    image: mongo:5.0
    container_name: \"${PLATFORM_NAME}-mongodb\"
    ports:
      - \"27017:27017\"
    hostname: mongodb
    volumes:
      - mongodb_data:/data/db
    environment:
      - MONGO_INITDB_DATABASE=video-analysis
    networks:
      - smartvision-net

volumes:
  mongodb_data:

networks:
  smartvision-net:
    driver: bridge" >> docker-compose.yml

  echo "🐳 Fichier docker-compose.yml créé avec:"
  echo "   - Services: ${SERVICES[*]}"
  echo "   - MongoDB pour le service video-analyzer"
}

# Fonction principale
main() {
  init_logging
  log "Début du déploiement - logs: ${LOG_FILE}"
  parse_arguments "$@"
  init_defaults
  check_prerequisites
  create_project_structure
  
  # Générer chaque microservice
  for SERVICE in "${SERVICES[@]}"; do
    generate_microservice "$SERVICE" "${SERVICE_PORTS[$SERVICE]}"
  done
  
  create_docker_compose
  
  echo -e "\n✅ Plateforme $PLATFORM_NAME générée avec succès!"
  echo "👉 Prochaines étapes:"
  echo "1. Ajouter vos fichiers de configuration dans $CONFIG_REPO_DIR"
  echo "2. Compiler les microservices : mvn clean package"
  echo "3. Démarrer la plateforme : docker-compose up --build"
  echo "4. Accéder aux services:"
  echo "   - Eureka: http://localhost:8761"
  echo "   - Config Server: http://localhost:8888"
  echo "   - API Gateway: http://localhost:8080"
  echo ""
  echo "📦 Classes principales générées:"
  for SERVICE in "${SERVICES[@]}"; do
  	local CLASS_NAME=$(to_camel_case "$SERVICE")Application
  	local PACKAGE_NAME=$(format_package_name "$SERVICE")
  	echo "   - $SERVICE: $GROUP_ID.$PACKAGE_NAME.$CLASS_NAME"
  done
}

# Point d'entrée
main "$@"
