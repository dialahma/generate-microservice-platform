#!/bin/bash

##############################################
# 🚀 SmartVision Platform Generator V3
##############################################

GREEN='\033[0;32m'
NC='\033[0m'

# 🎨 Fonctions utilitaires
to_camel_case() { echo "$1" | sed -r 's/(^|-)([a-z])/\U\2/g'; }
package_format() { echo "$1" | tr '-' '_'; }

# 🔗 Mapping Spring Cloud
declare -A SPRING_CLOUD_VERSIONS=(
  ["3.4.7"]="2024.0.1"
  ["3.3.0"]="2023.0.1"
  ["3.2.0"]="2023.0.0"
)

# Liste des services + ports
SERVICES=("config-server" "eureka-server" "api-gateway" "video-core" "video-analyzer" "video-storage")
declare -A SERVICE_PORTS=(
  ["config-server"]=8888
  ["eureka-server"]=8761
  ["api-gateway"]=8080
  ["video-core"]=8081
  ["video-analyzer"]=8082
  ["video-storage"]=8083
)

# 📂 Repo config initial
init_config_repo() {
  echo -e "${GREEN}🚀 Initialisation du config-repo${NC}"
  mkdir -p "$INIT_REPO_PATH"
  cd "$INIT_REPO_PATH" || exit 1
  cat <<EOF > application.yml
spring:
  application:
    name: config-repo
EOF
  git init
  git add application.yml
  git commit -m "Initial commit"
}

# 📂 .gitignore global
generate_gitignore() {
  cat <<EOF > "$PLATFORM_NAME/.gitignore"
target/
.idea/
*.iml
.DS_Store
*.log
EOF
}

# 📄 README.md
generate_readme() {
  cat <<EOF > "$PLATFORM_NAME/README.md"
# $PLATFORM_NAME

## Services & Ports

EOF
  for SERVICE in "${SERVICES[@]}"; do
    echo "- $SERVICE : ${SERVICE_PORTS[$SERVICE]}" >> "$PLATFORM_NAME/README.md"
  done
}

# ⚙️ Génération microservice
create_service() {
  SERVICE_NAME=$1
  CAMEL_CASE_NAME=$(to_camel_case "$SERVICE_NAME")
  PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  PORT=${SERVICE_PORTS[$SERVICE_NAME]}
  SERVICE_DIR="$PLATFORM_NAME/$SERVICE_NAME"

  mkdir -p "$SERVICE_DIR/src/main/java" "$SERVICE_DIR/src/main/resources"

  DEPENDENCIES=""
  ANNOTATION=""

  case "$SERVICE_NAME" in
  "config-server")
    DEPENDENCIES="<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-config-server</artifactId>
</dependency>"
    IMPORTS="import org.springframework.cloud.config.server.EnableConfigServer;"
    ANNOTATION='@Profile("!test")
@EnableConfigServer'
    ;;

  "eureka-server")
    DEPENDENCIES="<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
</dependency>"
    IMPORTS="import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;"
    ANNOTATION='@Profile("!test")
@EnableEurekaServer'
    ;;

  "api-gateway")
    DEPENDENCIES="<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-starter-gateway</artifactId>
</dependency>"
    IMPORTS=""  # Pas de @EnableXxx spécifique
    ANNOTATION='@Profile("!test")'
    ;;

  *)
    # Pour les services vidéo ou autres génériques
    DEPENDENCIES="" 
    IMPORTS="" 
    ANNOTATION='@Profile("!test")'
    ;;
esac


  PACKAGE_DIR=$(echo "$GROUP_ID" | sed 's/\./\//g')/$PACKAGE_SAFE
  mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR"

  # pom.xml
  cat <<EOF > "$SERVICE_DIR/pom.xml"
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
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-actuator</artifactId></dependency>
    $DEPENDENCIES
    <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
    <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
  </dependencies>
  <dependencyManagement>
    <dependencies>
      <dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-dependencies</artifactId><version>\${spring-cloud.version}</version><type>pom</type><scope>import</scope></dependency>
    </dependencies>
  </dependencyManagement>
</project>
EOF

  # Application.java
  cat <<EOF > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/${CAMEL_CASE_NAME}Application.java"
package $GROUP_ID.$PACKAGE_SAFE;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Profile;
$IMPORTS

$ANNOTATION
@SpringBootApplication
public class ${CAMEL_CASE_NAME}Application {
  public static void main(String[] args) {
    SpringApplication.run(${CAMEL_CASE_NAME}Application.class, args);
  }
}
EOF

  # Tests
  TEST_DIR="$SERVICE_DIR/src/test/java/$PACKAGE_DIR"
  mkdir -p "$TEST_DIR" "$SERVICE_DIR/src/test/resources"

  cat <<EOF > "$TEST_DIR/${CAMEL_CASE_NAME}ApplicationTests.java"
package $GROUP_ID.$PACKAGE_SAFE;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ${CAMEL_CASE_NAME}ApplicationTests {
  @Test void contextLoads() {}
}
EOF

  cat <<EOF > "$SERVICE_DIR/src/test/resources/application-test.yml"
spring:
  cloud:
    config:
      enabled: false
eureka:
  client:
    enabled: false
EOF

  # bootstrap.yml
  cat <<EOF > "$SERVICE_DIR/src/main/resources/bootstrap.yml"
spring:
  application:
    name: $SERVICE_NAME
  cloud:
    config:
      uri: http://localhost:8888
eureka:
  client:
    service-url:
      defaultZone: http://localhost:8761/eureka/
EOF

  echo "server:
  port: $PORT" > "$SERVICE_DIR/src/main/resources/application.yml"

  # Dockerfile
  cat <<EOF > "$SERVICE_DIR/Dockerfile"
FROM eclipse-temurin:$JAVA_VERSION-jdk-alpine
VOLUME /tmp
COPY "target/${SERVICE}-0.0.1-SNAPSHOT.jar" app.jar
ENTRYPOINT ["java","-jar","/app.jar"]
EOF

  echo -e "${GREEN}✅ $SERVICE_NAME généré avec port $PORT${NC}"
}

# 🐳 docker-compose.yml
generate_docker_compose() {
  cat <<EOF > "$PLATFORM_NAME/docker-compose.yml"
version: '3.8'

services:
EOF

  for SERVICE in "${SERVICES[@]}"; do
    PORT=${SERVICE_PORTS[$SERVICE]}
    cat <<EOF >> "$PLATFORM_NAME/docker-compose.yml"
  $SERVICE:
    build: ./$SERVICE
    container_name: $PLATFORM_NAME-$SERVICE
    ports:
      - "$PORT:$PORT"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$PORT/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF
    if [[ "$SERVICE" != "config-server" ]]; then
      echo "    depends_on:" >> "$PLATFORM_NAME/docker-compose.yml"
      echo "      config-server:" >> "$PLATFORM_NAME/docker-compose.yml"
      echo "        condition: service_healthy" >> "$PLATFORM_NAME/docker-compose.yml"
    fi
    if [[ "$SERVICE" == "api-gateway" || "$SERVICE" == "video-core" || "$SERVICE" == "video-analyzer" || "$SERVICE" == "video-storage" ]]; then
      echo "      eureka-server:" >> "$PLATFORM_NAME/docker-compose.yml"
      echo "        condition: service_healthy" >> "$PLATFORM_NAME/docker-compose.yml"
    fi
  done
}

main() {
  [[ "$INIT_CONFIG_REPO" == true ]] && init_config_repo
  SPRINGCLOUD_VERSION="${SPRING_CLOUD_VERSIONS[$SPRINGBOOT_VERSION]}"
  [[ "$FORCE" == true ]] && rm -rf "$PLATFORM_NAME"
  mkdir -p "$PLATFORM_NAME"
  generate_gitignore
  generate_readme
  for SERVICE in "${SERVICES[@]}"; do create_service "$SERVICE"; done
  generate_docker_compose
  echo -e "${GREEN}🎉 Plateforme $PLATFORM_NAME générée avec succès !${NC}"
}

# 🎛️ Arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --platform-name) PLATFORM_NAME="$2"; shift ;;
    --group-id) GROUP_ID="$2"; shift ;;
    --java-version) JAVA_VERSION="$2"; shift ;;
    --springboot-version) SPRINGBOOT_VERSION="$2"; shift ;;
    --init-config-repo) INIT_CONFIG_REPO=true; INIT_REPO_PATH="$2"; shift ;;
    --force) FORCE=true ;;
    *) echo "❌ Argument inconnu $1"; exit 1 ;;
  esac
  shift
done

main

