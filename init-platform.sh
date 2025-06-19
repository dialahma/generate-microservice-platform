#!/bin/bash

PROJECT_NAME="video-surveillance-platform"
GROUP_ID="net.isco"
VERSION="1.0-SNAPSHOT"
SPRING_BOOT_VERSION="3.2.5"
JAVA_VERSION="17"

MODULES=("video-core" "video-streaming" "video-storage" "video-analysis" "face-recognition" "api-gateway" "config-server" "service-discovery" "client-ui" "common")
FORCE=false

declare -A SPRING_DEPENDENCIES
SPRING_DEPENDENCIES=(
  ["video-core"]=""
  ["video-streaming"]="spring-boot-starter-web"
  ["video-storage"]="spring-boot-starter-data-jpa"
  ["video-analysis"]="spring-boot-starter"
  ["face-recognition"]="spring-boot-starter"
  ["api-gateway"]="spring-cloud-starter-gateway"
  ["config-server"]="spring-cloud-config-server"
  ["service-discovery"]="spring-cloud-starter-netflix-eureka-server"
  ["client-ui"]="spring-boot-starter-thymeleaf"
  ["common"]=""
)

# .gitignore standard Java
GITIGNORE_CONTENT='
target/
.idea/
.vscode/
*.iml
*.log
*.jar
*.war
*.class
.DS_Store
'

# Parent POM
generate_parent_pom() {
cat <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>${GROUP_ID}</groupId>
    <artifactId>${PROJECT_NAME}</artifactId>
    <version>${VERSION}</version>
    <packaging>pom</packaging>

    <name>Video Surveillance Platform</name>

    <modules>
$(for module in "${MODULES[@]}"; do echo "        <module>$module</module>"; done)
    </modules>

    <properties>
        <java.version>${JAVA_VERSION}</java.version>
        <spring-boot.version>${SPRING_BOOT_VERSION}</spring-boot.version>
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
}

# Module POM
generate_module_pom() {
  local artifactId=$1
  local dependencies=${SPRING_DEPENDENCIES[$artifactId]}
  cat <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>

  <parent>
    <groupId>${GROUP_ID}</groupId>
    <artifactId>${PROJECT_NAME}</artifactId>
    <version>${VERSION}</version>
  </parent>

  <artifactId>${artifactId}</artifactId>
  <packaging>jar</packaging>

  <dependencies>
$(for dep in $dependencies; do
  echo "    <dependency><groupId>org.springframework.boot</groupId><artifactId>$dep</artifactId></dependency>"
done)
  </dependencies>

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
}

# Check for --force
if [[ "$1" == "--force" ]]; then
  FORCE=true
fi

# Delete if exists
if [ -d "$PROJECT_NAME" ]; then
  if [ "$FORCE" = true ]; then
    echo "🧨 Suppression de $PROJECT_NAME (mode --force)..."
    rm -rf "$PROJECT_NAME"
  else
    echo "❌ Le dossier $PROJECT_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi
fi

# Create base structure
echo "📁 Création de la structure du projet $PROJECT_NAME ..."
mkdir "$PROJECT_NAME"
cd "$PROJECT_NAME" || exit

generate_parent_pom > pom.xml

# Créer modules
for module in "${MODULES[@]}"; do
  echo "📦 Module : $module"
  mkdir -p "$module/src/main/java/${GROUP_ID//./\/}/$module"
  mkdir -p "$module/src/main/resources"
  mkdir -p "$module/src/test/java"

  generate_module_pom "$module" > "$module/pom.xml"

  # Application.java par défaut
  cat > "$module/src/main/java/${GROUP_ID//./\/}/$module/Application.java" <<EOF
package ${GROUP_ID}.${module};

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class Application {
  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }
}
EOF

  # application.yml minimal
  cat > "$module/src/main/resources/application.yml" <<EOF
spring:
  application:
    name: $module
EOF

done

# Git + gitignore
echo "$GITIGNORE_CONTENT" > .gitignore
git init > /dev/null
git add .
git commit -m "Initial Spring Boot project structure" > /dev/null

echo "✅ Projet Spring Boot multi-modules généré avec succès !"

