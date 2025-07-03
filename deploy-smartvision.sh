#!/bin/bash
# deploy-smartvision.sh
# Déploie la plateforme depuis n'importe quel emplacement

# Configuration modifiable via arguments
PLATFORM_DIR="${PLATFORM_DIR:-/app/workspace/java/video/smartvision-platform}"
CONFIG_REPO_DIR="${CONFIG_REPO_DIR:-/home/ahdiallo/smartvision-config-repo}"
LOG_DIR="${HOME}/.smartvision/logs"

# Options
FORCE_REBUILD=false
SKIP_TESTS=false
TAIL_LOGS=false

# Fonction pour afficher l'usage
usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -d, --dir PATH       Répertoire de la plateforme (défaut: $PLATFORM_DIR)"
  echo "  -c, --config PATH    Dossier de configuration (défaut: $CONFIG_REPO_DIR)"
  echo "  -f, --force          Force le rebuild complet des images Docker"
  echo "  -s, --skip-tests     Skip les tests Maven"
  echo "  -t, --tail-logs      Affiche les logs après déploiement"
  echo "  -h, --help           Affiche cette aide"
  echo
  echo "Variables d'environnement:"
  echo "  PLATFORM_DIR, CONFIG_REPO_DIR, LOG_DIR peuvent être définies"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--dir)
      PLATFORM_DIR="$2"
      shift 2
      ;;
    -c|--config)
      CONFIG_REPO_DIR="$2"
      shift 2
      ;;
    -f|--force)
      FORCE_REBUILD=true
      shift
      ;;
    -s|--skip-tests)
      SKIP_TESTS=true
      shift
      ;;
    -t|--tail-logs)
      TAIL_LOGS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Option inconnue: $1"
      usage
      exit 1
      ;;
  esac
done

# Initialisation
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"
COMPOSE_FILE="$PLATFORM_DIR/docker-compose.yml"

# Fonction de logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Vérification du projet
verify_project_structure() {
  local missing=0
  
  if [ ! -d "$PLATFORM_DIR" ]; then
    log "❌ Répertoire de la plateforme introuvable: $PLATFORM_DIR"
    missing=$((missing+1))
  fi

  if [ ! -f "$COMPOSE_FILE" ]; then
    log "❌ Fichier docker-compose.yml introuvable dans $PLATFORM_DIR"
    missing=$((missing+1))
  fi

  return $missing
}

# Construction des services
build_services() {
  local mvn_args=()
  $SKIP_TESTS && mvn_args+=("-DskipTests")

  log "Construction des services dans $PLATFORM_DIR..."
  cd "$PLATFORM_DIR" || return 1

  find . -name "pom.xml" -print0 | while IFS= read -r -d '' pom_file; do
    service_dir=$(dirname "$pom_file")
    log "🔨 Building $service_dir..."
    (cd "$service_dir" && mvn clean package "${mvn_args[@]}") || {
      log "❌ Échec de la construction de $service_dir"
      return 1
    }
  done
}

# Déploiement Docker
deploy_platform() {
  local compose_args=("-d")
  $FORCE_REBUILD && compose_args+=("--build")

  log "🚀 Déploiement avec Docker Compose..."
  docker-compose -f "$COMPOSE_FILE" up "${compose_args[@]}" || {
    log "❌ Échec du déploiement Docker"
    return 1
  }
}

# Vérification des services
verify_deployment() {
  log "Vérification des services..."
  local success=0
  local services=("eureka-server" "config-server" "api-gateway")

  for service in "${services[@]}"; do
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "$service.*Up"; then
      log "✔️ $service est en cours d'exécution"
      ((success++))
    else
      log "⚠️ $service ne semble pas fonctionnel"
    fi
  done

  [ $success -eq ${#services[@]} ]
}

# Fonction principale
main() {
  log "Début du déploiement - logs: $LOG_FILE"
  log "-------------------------------------"
  log "Répertoire plateforme: $PLATFORM_DIR"
  log "Répertoire config: $CONFIG_REPO_DIR"
  log "Options:"
  log "  Force rebuild: $FORCE_REBUILD"
  log "  Skip tests: $SKIP_TESTS"

  # Vérifications initiales
  if ! verify_project_structure; then
    log "❌ Structure du projet invalide"
    exit 1
  fi

  # Construction
  if ! build_services; then
    exit 1
  fi

  # Déploiement
  if ! deploy_platform; then
    exit 1
  fi

  # Vérification
  if verify_deployment; then
    log "✅ Déploiement réussi!"
    log "URLs:"
    log "  Eureka: http://localhost:8761"
    log "  Config: http://localhost:8888"
    log "  API Gateway: http://localhost:8080"
  else
    log "⚠️ Déploiement partiellement réussi - certains services peuvent ne pas fonctionner"
  fi

  # Affichage des logs si demandé
  $TAIL_LOGS && {
    echo
    docker-compose -f "$COMPOSE_FILE" logs -f
  }
}

# Exécution
main
