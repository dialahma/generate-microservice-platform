#!/bin/bash

PROJECT_NAME="video-surveillance-platform"
FORCE=false

# .gitignore standard Java
GITIGNORE_CONTENT='
# Compiled class files
*.class

# Log file
*.log

# BlueJ files
*.ctxt

# Mobile Tools for Java (J2ME)
.mtj.tmp/

# Package Files #
*.jar
*.war
*.nar
*.ear
*.zip
*.tar.gz
*.rar

# Maven
target/
dependency-reduced-pom.xml
buildNumber.properties
release.properties

# Eclipse
.classpath
.project
.settings/

# IntelliJ
.idea/
*.iml
*.ipr
*.iws

# VS Code
.vscode/
'

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
mkdir -p "$PROJECT_NAME"/{video-core,video-streaming,video-storage,video-analysis,face-recognition,api-gateway,config-server,service-discovery,client-ui,common}
cd "$PROJECT_NAME" || exit

# Créer pom.xml parent
cat > pom.xml <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>video-surveillance-platform</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>pom</packaging>

    <modules>
        <module>video-core</module>
        <module>video-streaming</module>
        <module>video-storage</module>
        <module>video-analysis</module>
        <module>face-recognition</module>
        <module>api-gateway</module>
        <module>config-server</module>
        <module>service-discovery</module>
        <module>client-ui</module>
        <module>common</module>
    </modules>

    <name>Video Surveillance Platform</name>
</project>
EOF

# Créer .gitignore
echo "📝 Création du .gitignore ..."
echo "$GITIGNORE_CONTENT" > .gitignore

# Initialiser git
echo "🔧 Initialisation du dépôt git ..."
git init > /dev/null
git add .
git commit -m "Initial commit: project structure" > /dev/null

echo "✅ Projet $PROJECT_NAME généré avec succès !"

