#!/bin/bash

set -e

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

# Vérification des dépendances
for tool in java mvn; do
  if ! command -v $tool &>/dev/null; then
    echo "❌ $tool est requis mais non trouvé"
    exit 1
  fi
done

# Force : suppression des anciens projets
if [ "$FORCE" = true ]; then
  echo "🧨 Suppression des anciens projets liés à Spring Boot (video-* et $PROJECT_NAME)..."
  find . -maxdepth 1 -type d \( -name "video-*" -o -name "$PROJECT_NAME" \) -exec rm -rf {} +
fi

# Création dossier principal
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

##############################
### Génération pom parent ###
##############################
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
    <module>video-analyzer</module>
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
</project>
EOF

#####################################
### Fonction création microservice ###
#####################################
create_service() {
  local name="$1"
  local pkg="com.$PROJECT_NAME.$name"
  mkdir -p "$name/src/main/java/${pkg//.//}" "$name/src/main/resources"

  # pom.xml
  cat > "$name/pom.xml" <<EOF
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

  if [[ "$name" == "eureka-server" ]]; then
    echo '<dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-netflix-eureka-server</artifactId></dependency>' >> "$name/pom.xml"
  elif [[ "$name" == "config-server" ]]; then
    cat >> "$name/pom.xml" <<EOD
<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-config-server</artifactId>
</dependency>
<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
</dependency>
EOD
  elif [[ "$name" == "api-gateway" ]]; then
    cat >> "$name/pom.xml" <<EOD
<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-starter-gateway</artifactId>
</dependency>
<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
</dependency>
EOD
  elif [[ "$name" == "video-analyzer" ]]; then
    cat >> "$name/pom.xml" <<EOD
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-web</artifactId>
</dependency>
<dependency>
  <groupId>org.springframework.cloud</groupId>
  <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
</dependency>
<dependency>
  <groupId>nu.pattern</groupId>
  <artifactId>opencv</artifactId>
  <version>4.7.0-0</version>
</dependency>
EOD
  else
    echo '<dependency><groupId>org.springframework.cloud</groupId><artifactId>spring-cloud-starter-netflix-eureka-client</artifactId></dependency>' >> "$name/pom.xml"
  fi

  cat >> "$name/pom.xml" <<EOF
  </dependencies>
</project>
EOF

  # Application.java
  local app_file="$name/src/main/java/${pkg//.//}/Application.java"
  echo "package $pkg;" > "$app_file"
  echo "" >> "$app_file"
  echo "import org.springframework.boot.SpringApplication;" >> "$app_file"
  echo "import org.springframework.boot.autoconfigure.SpringBootApplication;" >> "$app_file"
  echo "" >> "$app_file"
  echo "@SpringBootApplication" >> "$app_file"
  echo "public class Application {" >> "$app_file"
  echo "  public static void main(String[] args) {" >> "$app_file"
  if [[ "$name" == "video-analyzer" ]]; then
    echo "    nu.pattern.OpenCV.loadLocally();" >> "$app_file"
  fi
  echo "    SpringApplication.run(Application.class, args);" >> "$app_file"
  echo "  }" >> "$app_file"
  echo "}" >> "$app_file"

  # application.yml
  cat > "$name/src/main/resources/application.yml" <<EOF
spring:
  application:
    name: $name
server:
  port: 0
EOF

  # bootstrap.yml
  cat > "$name/src/main/resources/bootstrap.yml" <<EOF
spring:
  application:
    name: $name
  cloud:
    config:
      uri: http://localhost:8888
EOF
}

####################################
### Création des microservices ###
####################################
for svc in eureka-server config-server api-gateway video-core video-analyzer; do
  echo "📦 Création du module $svc..."
  create_service "$svc"
done

# .gitignore global
cat > .gitignore <<EOF
/target
/.idea
*.iml
*.log
*.tmp
.DS_Store
EOF

echo "✅ Plateforme $PROJECT_NAME générée avec succès !"

