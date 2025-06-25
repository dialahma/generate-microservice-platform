#!/bin/bash

set -e

PROJECT_NAME=""
JAVA_VERSION="17"
SPRING_BOOT_VERSION="3.2.5"
SPRING_CLOUD_VERSION="2023.0.1"
GROUP_ID="com.example"
FORCE=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --project-name=*) PROJECT_NAME="${arg#*=}" ;;
    --java-version=*) JAVA_VERSION="${arg#*=}" ;;
    --springboot-version=*) SPRING_BOOT_VERSION="${arg#*=}" ;;
    --group-id=*) GROUP_ID="${arg#*=}" ;;
    --force) FORCE=true ;;
    *) echo "Option inconnue : $arg"; exit 1 ;;
  esac
done

if [ -z "$PROJECT_NAME" ]; then
  echo "⚠️  Veuillez spécifier --project-name"
  exit 1
fi

for tool in java mvn; do
  if ! command -v $tool &>/dev/null; then
    echo "❌ $tool est requis mais non trouvé"
    exit 1
  fi
done

if [ "$FORCE" = true ]; then
  echo "🧨 Suppression des anciens projets..."
  rm -rf "$PROJECT_NAME"
fi

mkdir -p "$PROJECT_NAME/microservices"
cd "$PROJECT_NAME"

# Conversion vers CamelCase
to_camel_case() {
  echo "$1" | sed -r 's/(^|-)([a-z])/\u\2/g'
}

create_service() {
  local name="$1"
  local path="microservices/$name"
  local class_name="$(to_camel_case "$name")Application"
  local package_suffix="${name//-/_}"
  local java_dir="$path/src/main/java/${GROUP_ID//.//}/$package_suffix"

  mkdir -p "$java_dir"
  mkdir -p "$path/src/main/resources"

  # pom.xml
  cat > "$path/pom.xml" <<-EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$name</artifactId>
  <version>1.0.0</version>
  <properties>
    <java.version>$JAVA_VERSION</java.version>
    <spring.boot.version>$SPRING_BOOT_VERSION</spring.boot.version>
    <spring.cloud.version>$SPRING_CLOUD_VERSION</spring.cloud.version>
  </properties>
  <repositories>
    <repository>
      <id>spring-releases</id>
      <url>https://repo.spring.io/release</url>
    </repository>
  </repositories>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-dependencies</artifactId>
        <version>\${spring.cloud.version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter</artifactId>
      <version>\${spring.boot.version}</version>
    </dependency>
EOF

  if [[ "$name" == "eureka-server" ]]; then
    cat >> "$path/pom.xml" <<-EOD
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
    </dependency>
    <dependency>
       <groupId>ch.qos.logback</groupId>
       <artifactId>logback-classic</artifactId>
    </dependency>
EOD
  elif [[ "$name" == "config-server" ]]; then
    cat >> "$path/pom.xml" <<-EOD
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-config-server</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
       <groupId>ch.qos.logback</groupId>
       <artifactId>logback-classic</artifactId>
    </dependency>
EOD
  elif [[ "$name" == "api-gateway" ]]; then
    cat >> "$path/pom.xml" <<-EOD
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-gateway</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
       <groupId>ch.qos.logback</groupId>
       <artifactId>logback-classic</artifactId>
    </dependency>
EOD
  else
    cat >> "$path/pom.xml" <<-EOD
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
    <dependency>
      <groupId>org.postgresql</groupId>
      <artifactId>postgresql</artifactId>
      <version>42.7.3</version>
    </dependency>
    <dependency>
      <groupId>com.google.code.gson</groupId>
      <artifactId>gson</artifactId>
      <version>2.10.1</version>
    </dependency>
    <dependency>
       <groupId>ch.qos.logback</groupId>
       <artifactId>logback-classic</artifactId>
    </dependency>
EOD
  fi

  cat >> "$path/pom.xml" <<-EOF
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
        <version>\${spring.boot.version}</version>
        <executions>
          <execution>
            <goals>
              <goal>repackage</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.10.1</version>
        <configuration>
          <source>\${java.version}</source>
          <target>\${java.version}</target>
          <release>\${java.version}</release>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF
  # Classe Java principale
  cat > "$java_dir/${class_name}.java" <<-EOF
package ${GROUP_ID}.${package_suffix};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
EOF

  if [[ "$name" == "eureka-server" ]]; then
    echo "import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;" >> "$path/src/main/java/${GROUP_ID//.//}/$package_suffix/${class_name}.java"
    echo "" >> "$path/src/main/java/${GROUP_ID//.//}/$package_suffix/${class_name}.java"
    echo "@EnableEurekaServer" >> "$path/src/main/java/${GROUP_ID//.//}/$package_suffix/${class_name}.java"
  elif [[ "$name" == "config-server" ]]; then
    echo "import org.springframework.cloud.config.server.EnableConfigServer;" >> "$path/src/main/java/${GROUP_ID//.//}/$package_suffix/${class_name}.java"
    echo "" >> "$path/src/main/java/${GROUP_ID//.//}/$package_suffix/${class_name}.java"
    echo "@EnableConfigServer" >> "$path/src/main/java/${GROUP_ID//.//}/$package_suffix/${class_name}.java"
  fi

  cat >> "$java_dir/${class_name}.java" <<-EOF
@SpringBootApplication
public class ${class_name} {
  public static void main(String[] args) {
    SpringApplication.run(${class_name}.class, args);
  }
}
EOF

  cat > "$path/src/main/resources/application.yml" <<-EOF
spring:
  application:
    name: $name
  cloud:
    config:
      uri: http://localhost:8888
server:
  port: 0
EOF

# Dockerfile multi-stage
  cat > "$path/Dockerfile" <<-EOF
FROM maven:3.9.6-eclipse-temurin-${JAVA_VERSION}-alpine AS build
WORKDIR /app
COPY . .
RUN mvn clean package -DskipTests

FROM eclipse-temurin:${JAVA_VERSION}-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
}

# Liste des services
SERVICES=(eureka-server config-server api-gateway video-core video-analyzer video-storage)
for svc in "${SERVICES[@]}"; do
  echo "📦 Génération du service $svc..."
  create_service "$svc"
done

cat > docker-compose.yml <<-EOF
version: '3.9'
services:
EOF
for svc in "${SERVICES[@]}"; do
  cat >> docker-compose.yml <<-EOL
  $svc:
    build: ./microservices/$svc
    ports:
      - "0"
EOL
done

cat > .gitignore <<-EOF
/target
/.idea
*.iml
*.log
.DS_Store
EOF

echo "✅ Plateforme $PROJECT_NAME générée avec microservices autonomes et configurations complètes."

