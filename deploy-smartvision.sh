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

verify_jar() {
  local SERVICE=$1
  local JAR_PATH="./$SERVICE/target/$SERVICE-0.0.1-SNAPSHOT.jar"
  
  if [ ! -f "$JAR_PATH" ]; then
    echo "❌ ERREUR : Fichier JAR introuvable pour $SERVICE"
    echo "Chemin attendu : $JAR_PATH"
    echo "Fichiers trouvés :"
    ls -lh "./$SERVICE/target/" || echo "Aucun fichier dans target/"
    exit 1
  fi
  
  echo "✔️ JAR trouvé pour $SERVICE (taille : $(du -h "$JAR_PATH" | cut -f1))"
}

# Construction des services
build_services() {
  local mvn_args=()
  $SKIP_TESTS && mvn_args+=("-DskipTests")

  log "🔨 Construction des services dans l'ordre correct..."
  cd "$PLATFORM_DIR" || return 1

  # D'abord construire Eureka Server avec tests désactivés
  log "🔨 Building eureka-server (tests forcément skip)..."
  (cd "eureka-server" && mvn clean package -DskipTests) || {
    log "❌ Échec de la construction de eureka-server"
    return 1
  }
  verify_jar "eureka-server"

  # Puis les autres services
  SERVICES_ORDER=("config-server" "api-gateway" "video-core" "video-analyzer" "video-storage")
  
  for SERVICE in "${SERVICES_ORDER[@]}"; do
    log "🔨 Building $SERVICE..."
    (cd "$SERVICE" && mvn clean package "${mvn_args[@]}") || {
      log "❌ Échec de la construction de $SERVICE"
      return 1
    }
    verify_jar "$SERVICE"
  done
  
  # Construction Docker
  log "🐳 Construction des images Docker..."
  docker-compose build --no-cache || {
    log "❌ Échec de la construction des images Docker"
    exit 1
  }
}

# Déploiement Docker
deploy_platform() {
    local compose_args=("-d")
  $FORCE_REBUILD && compose_args+=("--build")
  MAX_WAIT=120
  SECONDS_WAITED=0

  log "🚀 Déploiement avec ordre contrôlé..."
  
  # Démarrer d'abord les services essentiels
  log "⏳ Démarrage de MongoDB..."
  docker-compose up -d mongodb
  
  log "⏳ Attente du démarrage de MongoDB..."
  while ! docker-compose exec -T mongodb mongo --eval "db.adminCommand('ping')" >/dev/null 2>&1; do
    sleep 5
  done
  
  if ! git -C "$CONFIG_REPO_DIR" show-ref --verify --quiet refs/heads/main; then
    log "❌ La branche 'main' est absente dans le dépôt $CONFIG_REPO_DIR"
    log "ℹ️ Branche disponible : $(git -C "$CONFIG_REPO_DIR" branch --show-current)"
    exit 1
  fi
  
  log "⏳ Démarrage du Config Server..."
  docker-compose up -d config-server
  
  log "⏳ Attente du Config Server (max ${MAX_WAIT}s)..."
  
  if [ ! -f "$HOME/smartvision-config-repo/api-gateway.yml" ]; then
    echo "❌ Le fichier api-gateway.yml est manquant dans smartvision-config-repo"
    exit 1
  fi

  if ! git -C "$HOME/smartvision-config-repo" rev-parse --verify main > /dev/null 2>&1; then
    echo "❌ La branche 'main' est absente ou incorrecte dans smartvision-config-repo"
    exit 1
  fi

  log "⏳ Attente du Config Server..."
  while ! curl -s http://localhost:8888/actuator/health | grep -q '"status":"UP"' || [ $SECONDS_WAITED -ge $MAX_WAIT ]; do
    sleep 5
    SECONDS_WAITED=$((SECONDS_WAITED + 5))
  done
  if [ $SECONDS_WAITED -ge $MAX_WAIT ]; then
    log "⚠️ Timeout atteint. Le Config Server est lent ou instable (status = $(curl -s http://localhost:8888/actuator/health))."
  else
    log "✔️ Config Server opérationnel après ${SECONDS_WAITED}s"
  fi
  
  log "⏳ Démarrage d'Eureka Server..."
  docker-compose up -d eureka-server
  
  log "⏳ Attente d'Eureka Server (max ${MAX_WAIT}s)..."
  while ! curl -s http://localhost:8761/actuator/health | grep -q '"status":"UP"'; do
    sleep 5
  done 
  
  # Démarrer les autres services
  log "⏳ Démarrage des autres services..."
  docker-compose up -d api-gateway video-core video-analyzer video-storage
  
  log "✅ Tous les services ont été démarrés"
}

# Vérification des services
verify_deployment() {
  log "Vérification des services..."
  local success=0
  local services=("eureka-server" "config-server" "api-gateway" "video-core" "video-storage" "video-analyzer")

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
    log "  API Gateway: http://localhost:8084"
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
