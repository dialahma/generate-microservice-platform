#!/bin/bash

set -e

# Colors
GREEN="\e[32m"
RED="\e[31m"
RESET="\e[0m"

# Default values
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-name)
      PROJECT_NAME=$2
      shift 2
      ;;
    --java-version)
      JAVA_VERSION=$2
      shift 2
      ;;
    --spring-boot-version)
      SB_VERSION=$2
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    *)
      echo -e "${RED}Unknown option: $1${RESET}"
      exit 1
      ;;
  esac
done

# Check required args
if [[ -z "$PROJECT_NAME" || -z "$JAVA_VERSION" || -z "$SB_VERSION" ]]; then
  echo -e "${RED}Usage: $0 --project-name NAME --java-version VERSION --spring-boot-version VERSION [--force]${RESET}"
  exit 1
fi

# Check Java
if ! type -p java > /dev/null; then
  echo -e "${RED}Java not found in PATH${RESET}"
  exit 1
fi

# Check Maven
if ! type -p mvn > /dev/null; then
  echo -e "${RED}Maven not found in PATH${RESET}"
  exit 1
fi

# Setup
BASE_DIR="$PWD/$PROJECT_NAME"

if [[ -d "$BASE_DIR" && "$FORCE" != true ]]; then
  echo -e "${RED}Directory $BASE_DIR already exists. Use --force to overwrite.${RESET}"
  exit 1
elif [[ -d "$BASE_DIR" ]]; then
  rm -rf "$BASE_DIR"
fi

mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

echo -e "${GREEN}Creating project structure...${RESET}"

# Generate .gitignore
cat > .gitignore <<EOF
/target
/.idea
*.iml
*.log
*.tmp
.DS_Store
EOF

# Parent POM
cat > pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.videosurv</groupId>
  <artifactId>$PROJECT_NAME</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <packaging>pom</packaging>
  <modules>
    <module>eureka-server</module>
    <module>config-server</module>
    <module>api-gateway</module>
    <module>video-streaming</module>
    <module>object-detection</module>
    <module>object-tracking</module>
    <module>face-recognition</module>
    <module>video-storage</module>
  </modules>
  <properties>
    <java.version>$JAVA_VERSION</java.version>
    <spring-boot.version>$SB_VERSION</spring-boot.version>
  </properties>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-dependencies</artifactId>
        <version>\${spring-boot.version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
</project>
EOF

# Function to create each service
generate_service() {
  SERVICE_NAME=$1
  PACKAGE_NAME="com.videosurv.$SERVICE_NAME"

  mkdir -p "$SERVICE_NAME/src/main/java/${PACKAGE_NAME//.//}"
  mkdir -p "$SERVICE_NAME/src/main/resources"

  cat > "$SERVICE_NAME/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.videosurv</groupId>
    <artifactId>$PROJECT_NAME</artifactId>
    <version>0.0.1-SNAPSHOT</version>
  </parent>
  <artifactId>$SERVICE_NAME</artifactId>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
    </dependency>
  </dependencies>
</project>
EOF

  # Application.java
  cat > "$SERVICE_NAME/src/main/java/${PACKAGE_NAME//.//}/Application.java" <<EOF
package $PACKAGE_NAME;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }
}
EOF

  # application.yml
  cat > "$SERVICE_NAME/src/main/resources/application.yml" <<EOF
spring:
  application:
    name: $SERVICE_NAME
server:
  port: 0
EOF
}

# Generate all services
SERVICES=(eureka-server config-server api-gateway video-streaming object-detection object-tracking face-recognition video-storage)
for svc in "${SERVICES[@]}"; do
  generate_service $svc
done

# Docker Compose
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  eureka-server:
    build: ./eureka-server
    ports:
      - "8761:8761"

  config-server:
    build: ./config-server
    ports:
      - "8888:8888"

  api-gateway:
    build: ./api-gateway
    ports:
      - "8080:8080"
EOF

echo -e "${GREEN}✅ Projet généré dans : $BASE_DIR${RESET}"

