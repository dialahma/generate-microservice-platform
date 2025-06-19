#!/bin/bash

PROJECT_NAME="video-surveillance-platform"
MODULES=("video-core" "video-streaming" "video-storage" "video-analysis" "face-recognition" "api-gateway" "config-server" "service-discovery" "client-ui" "common")
FORCE=false

# .gitignore standard Java
GITIGNORE_CONTENT='
# Build
target/
out/

# IntelliJ
.idea/
*.iml

# Eclipse
.project
.classpath
.settings/

# VS Code
.vscode/

# Logs
*.log

# Packages
*.jar
*.war
*.ear

# OS files
.DS_Store
Thumbs.db
'

# POM de base pour les sous-modules
generate_module_pom() {
cat <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>com.example</groupId>
        <artifactId>$PROJECT_NAME</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>$1</artifactId>
</project>
EOF
}

# Check for --force
if [[ "$1" == "--force" ]]; then
  FORCE=true
fi

# Delete existing folder if --force
if [ -d "$PROJECT_NAME" ]; then
  if [ "$FORCE" = true ]; then
    echo "🧨 Suppression de $PROJECT_NAME (mode --force)..."
    rm -rf "$PROJECT_NAME"
  else
    echo "❌ Le dossier $PROJECT_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi
fi

# Create base project structure
echo "📁 Création de la structure du projet $PROJECT_NAME ..."
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME" || exit

# Créer pom.xml parent
cat > pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>$PROJECT_NAME</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>pom</packaging>

    <modules>
$(for module in "${MODULES[@]}"; do echo "        <module>$module</module>"; done)
    </modules>

    <name>Video Surveillance Platform</name>
</project>
EOF

# Créer les modules et leur pom.xml
for module in "${MODULES[@]}"; do
  echo "📦 Création du module $module ..."
  mkdir -p "$module/src/main/java" "$module/src/test/java"
  generate_module_pom "$module" > "$module/pom.xml"
done

# Créer .gitignore
echo "📝 Création du .gitignore ..."
echo "$GITIGNORE_CONTENT" > .gitignore

# Initialiser git
echo "🔧 Initialisation du dépôt git ..."
git init > /dev/null
git add .
git commit -m "Initial commit: project structure with modules" > /dev/null

echo "✅ Projet $PROJECT_NAME généré avec succès avec tous les modules !"

