#!/bin/bash

set -e

# Default values
PROJECT_NAME=""
JAVA_VERSION="17"
SPRING_BOOT_VERSION="3.2.5"
FORCE=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --project-name=*)
      PROJECT_NAME="${arg#*=}"
      ;;
    --java-version=*)
      JAVA_VERSION="${arg#*=}"
      ;;
    --springboot-version=*)
      SPRING_BOOT_VERSION="${arg#*=}"
      ;;
    --force)
      FORCE=true
      ;;
    *)
      echo "Option inconnue : $arg"
      exit 1
      ;;
  esac
done

if [ -z "$PROJECT_NAME" ]; then
  echo "⚠️  Veuillez spécifier --project-name"
  exit 1
fi

# Vérification Java et Maven
if ! command -v java &>/dev/null; then
  echo "❌ Java n'est pas installé"
  exit 1
fi
if ! command -v mvn &>/dev/null; then
  echo "❌ Maven n'est pas installé"
  exit 1
fi

# Création du répertoire principal
if [ "$FORCE" = true ]; then
  echo "🧨 Suppression des projets existants dans le répertoire courant (mode --force)..."
  rm -rf "$PROJECT_NAME"
  find . -maxdepth 1 -type d -name "video-*" -exec rm -rf {} +
else
  if [ -d "$PROJECT_NAME" ]; then
    echo "❌ Le dossier $PROJECT_NAME existe déjà. Utilisez --force pour l’écraser."
    exit 1
  fi
fi


mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Création parent pom.xml
cat > pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.$PROJECT_NAME</groupId>
  <artifactId>$PROJECT_NAME</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>

  <modules>
    <module>eureka-server</module>
    <module>config-server</module>
    <module>api-gateway</module>
    <module>video-core</module>
  </modules>

  <properties>
    <java.version>$JAVA_VERSION</java.version>
    <spring-boot.version>$SPRING_BOOT_VERSION</spring-boot.version>
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

  <build>
    <pluginManagement>
      <plugins>
        <plugin>
          <groupId>org.springframework.boot</groupId>
          <artifactId>spring-boot-maven-plugin</artifactId>
        </plugin>
      </plugins>
    </pluginManagement>
  </build>
</project>
EOF

# Fonction pour générer un microservice
create_microservice() {
  local name=$1
  shift
  mkdir "$name"
  cd "$name"

  # pom.xml du module
  cat > pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.$PROJECT_NAME</groupId>
    <artifactId>$PROJECT_NAME</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>$name</artifactId>

  <dependencies>
EOF

  case $name in
    eureka-server)
      cat >> pom.xml <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
    </dependency>
EOF
      ;;
    config-server)
      cat >> pom.xml <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-config-server</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
EOF
      ;;
    api-gateway)
      cat >> pom.xml <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-gateway</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
EOF
      ;;
    *)
      cat >> pom.xml <<EOF
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
EOF
      ;;
  esac

  cat >> pom.xml <<EOF
  </dependencies>
</project>
EOF

  # arborescence minimale
  mkdir -p src/main/java/com/"$PROJECT_NAME"/"$name"
  mkdir -p src/main/resources

  # Fichiers de configuration
  cat > src/main/resources/application.yml <<EOF
server:
  port: 0

spring:
  application:
    name: $name
EOF

  cat > src/main/resources/bootstrap.yml <<EOF
spring:
  application:
    name: $name
  cloud:
    config:
      uri: http://localhost:8888
EOF

  cd ..
}

# Générer les microservices
create_microservice "eureka-server"
create_microservice "config-server"
create_microservice "api-gateway"
create_microservice "video-core"

# .gitignore
cat > .gitignore <<EOF
/target
**/target
*.iml
.idea/
/.mvn/
/logs/
/out/
*.log
EOF

echo "✅ Projet $PROJECT_NAME généré avec succès."

