#!/bin/bash

# Valeurs par défaut
PROJECT_NAME="video-surveillance-platform"
GROUP_ID="com.example"
VERSION="1.0-SNAPSHOT"
JAVA_VERSION="17"
SPRING_BOOT_VERSION="3.2.5"
FORCE=false

# Liste des modules
MODULES=("video-core" "video-streaming" "video-storage" "video-analysis" "face-recognition" "api-gateway" "config-server" "service-discovery" "client-ui" "common")

# Dépendances Spring par module
declare -A SPRING_DEPENDENCIES=(
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

# Gitignore standard Java
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

# Argument parser
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) PROJECT_NAME="$2"; shift ;;
        --java) JAVA_VERSION="$2"; shift ;;
        --springboot) SPRING_BOOT_VERSION="$2"; shift ;;
        --force) FORCE=true ;;
        *) echo "❌ Option inconnue : $1" && exit 1 ;;
    esac
    shift
done

# Vérification Java
if ! command -v java &>/dev/null; then
    echo "❌ Java n'est pas installé. Veuillez l'installer avant de continuer."
    exit 1
else
    echo "✅ Java trouvé : $(java -version 2>&1 | head -n 1)"
fi

# Vérification Maven
if ! command -v mvn &>/dev/null; then
    echo "❌ Maven n'est pas installé. Veuillez l'installer avant de continuer."
    exit 1
else
    echo "✅ Maven trouvé : $(mvn -v | head -n 1)"
fi

# Création du parent pom.xml
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

    <modules>
$(for module in "${MODULES[@]}"; do echo "        <module>$module</module>"; done)
    </modules>

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

# Création pom.xml pour module
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

# Supprimer dossier existant si --force
if [ -d "$PROJECT_NAME" ]; then
  if [ "$FORCE" = true ]; then
    echo "🧨 Suppression de $PROJECT_NAME (mode --force)..."
    rm -rf "$PROJECT_NAME"
  else
    echo "❌ Le dossier $PROJECT_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi
fi

# Création du projet
echo "📁 Création du projet : $PROJECT_NAME"
mkdir "$PROJECT_NAME"
cd "$PROJECT_NAME" || exit

generate_parent_pom > pom.xml

for module in "${MODULES[@]}"; do
  echo "📦 Génération du module : $module"
  mkdir -p "$module/src/main/java/${GROUP_ID//./\/}/$module"
  mkdir -p "$module/src/main/resources"
  mkdir -p "$module/src/test/java"

  generate_module_pom "$module" > "$module/pom.xml"

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

  cat > "$module/src/main/resources/application.yml" <<EOF
spring:
  application:
    name: $module
EOF

done

# Git init
echo "$GITIGNORE_CONTENT" > .gitignore
git init > /dev/null
git add .
git commit -m "Initial Spring Boot multi-module setup" > /dev/null

echo "✅ Projet $PROJECT_NAME généré avec succès avec Spring Boot $SPRING_BOOT_VERSION (Java $JAVA_VERSION) !"
#!/bin/bash

# Valeurs par défaut
PROJECT_NAME="video-surveillance-platform"
GROUP_ID="net.isco"
VERSION="1.0-SNAPSHOT"
JAVA_VERSION="17"
SPRING_BOOT_VERSION="3.2.5"
FORCE=false

# Liste des modules
MODULES=("video-core" "video-streaming" "video-storage" "video-analysis" "face-recognition" "api-gateway" "config-server" "service-discovery" "client-ui" "common")

# Dépendances Spring par module
declare -A SPRING_DEPENDENCIES=(
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

# Gitignore standard Java
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

# Argument parser
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) PROJECT_NAME="$2"; shift ;;
        --java) JAVA_VERSION="$2"; shift ;;
        --springboot) SPRING_BOOT_VERSION="$2"; shift ;;
        --force) FORCE=true ;;
        *) echo "❌ Option inconnue : $1" && exit 1 ;;
    esac
    shift
done

# Vérification Java
if ! command -v java &>/dev/null; then
    echo "❌ Java n'est pas installé. Veuillez l'installer avant de continuer."
    exit 1
else
    echo "✅ Java trouvé : $(java -version 2>&1 | head -n 1)"
fi

# Vérification Maven
if ! command -v mvn &>/dev/null; then
    echo "❌ Maven n'est pas installé. Veuillez l'installer avant de continuer."
    exit 1
else
    echo "✅ Maven trouvé : $(mvn -v | head -n 1)"
fi

# Création du parent pom.xml
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

    <modules>
$(for module in "${MODULES[@]}"; do echo "        <module>$module</module>"; done)
    </modules>

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

# Création pom.xml pour module
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

# Supprimer dossier existant si --force
if [ -d "$PROJECT_NAME" ]; then
  if [ "$FORCE" = true ]; then
    echo "🧨 Suppression de $PROJECT_NAME (mode --force)..."
    rm -rf "$PROJECT_NAME"
  else
    echo "❌ Le dossier $PROJECT_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi
fi

# Création du projet
echo "📁 Création du projet : $PROJECT_NAME"
mkdir "$PROJECT_NAME"
cd "$PROJECT_NAME" || exit

generate_parent_pom > pom.xml

for module in "${MODULES[@]}"; do
  echo "📦 Génération du module : $module"
  mkdir -p "$module/src/main/java/${GROUP_ID//./\/}/$module"
  mkdir -p "$module/src/main/resources"
  mkdir -p "$module/src/test/java"

  generate_module_pom "$module" > "$module/pom.xml"

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

  cat > "$module/src/main/resources/application.yml" <<EOF
spring:
  application:
    name: $module
EOF

done

# Git init
echo "$GITIGNORE_CONTENT" > .gitignore
git init > /dev/null
git add .
git commit -m "Initial Spring Boot multi-module setup" > /dev/null

echo "✅ Projet $PROJECT_NAME généré avec succès avec Spring Boot $SPRING_BOOT_VERSION (Java $JAVA_VERSION) !"

