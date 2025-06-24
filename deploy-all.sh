#!/bin/bash

set -e

BASE_DIR="$(pwd)"
SERVICES_DIR="$BASE_DIR/microservices"

if [ ! -d "$SERVICES_DIR" ]; then
  echo "❌ Dossier $SERVICES_DIR introuvable. Veuillez exécuter generate-platform.sh d'abord."
  exit 1
fi

# Compilation de chaque microservice
echo "🔧 Compilation des microservices..."

for service in "$SERVICES_DIR"/*; do
  if [ -d "$service" ] && [ -f "$service/pom.xml" ]; then
    # Vérifie la présence d'un artifactId non résolu
    if grep -q '<artifactId>\$svc</artifactId>' "$service/pom.xml"; then
      echo "❌ Erreur : artifactId mal généré dans $service/pom.xml"
      echo "➡️ Veuillez regénérer la plateforme avec l’option --force"
      exit 1
    fi

    echo "📦 Build de $(basename "$service")"
    (cd "$service" && mvn clean package -DskipTests)
  fi
done

# Lancement avec docker-compose
echo "🚀 Lancement de la plateforme avec Docker Compose..."
docker-compose -f "$BASE_DIR/docker-compose.yml" up --build -d

# Affichage de l'état
echo "✅ Tous les services sont lancés. Utilisez 'docker ps' pour vérifier."
docker ps --filter name=video-smart-platform_

