#!/bin/bash


# ============================================================================
# SmartVision Platform Generator — ULTIMATE EDITION (V7)
# ----------------------------------------------------------------------------
# • Spring Boot + Spring Cloud (Gateway + Config + Eureka)
# • Keycloak (OIDC) + Zipkin (tracing) + Prometheus + Grafana
# • Nginx Load Balancer + HAProxy + Redis Cache
# • Services: config-server, eureka-server, api-gateway,
#             video-core, video-analyzer, video-storage
# • Ports: GW=8084, CORE=8085, STORAGE=8083, ANALYZER=8082
# • Security: OAuth2, JWT, TLS, Rate Limiting
# • Monitoring: Prometheus, Grafana, Zipkin
# • Cache: Redis, Caffeine
# • Load Balancing: Nginx, HAProxy, Spring Cloud LoadBalancer
# ----------------------------------------------------------------------------
# Usage:
#   chmod +x generate-smartvision-ultimate.sh
#   ./generate-smartvision-ultimate.sh \
#     --platform-name smartvision-platform \
#     --group-id net.smart.vision \
#     --java-version 17 \
#     --springboot-version 3.4.7 \
#     --init-config-repo "$HOME/smartvision-config-repo" \
#     --force
#   cd smartvision-platform
#   ./deploy-smartvision.sh build && ./deploy-smartvision.sh up
# ============================================================================


GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 🎨 Fonctions utilitaires
log() { echo -e "${BLUE}📦 $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️ $1${NC}"; }

to_camel_case() { echo "$1" | sed -r 's/(^|-)([a-z])/\U\2/g'; }
package_format() { echo "$1" | tr '-' '_'; }

# 🔗 Mapping Spring Cloud
declare -A SPRING_CLOUD_VERSIONS=(
  ["3.4.7"]="2024.0.1"
  ["3.4.6"]="2024.0.1"
  ["3.3.3"]="2023.0.3"
  ["3.3.0"]="2023.0.1"
  ["3.2.0"]="2023.0.0"
)

# Variables globales
PLATFORM_NAME="smartvision-platform"
GROUP_ID="net.smart.vision"
JAVA_VERSION="17"
SPRINGBOOT_VERSION="3.4.7"
INIT_CONFIG_REPO=false
FORCE=false
INIT_REPO_PATH="$HOME/smartvision-config-repo"
SPRINGCLOUD_VERSION=""

# Images versions
MONGO_IMAGE="mongo:4.4"
KEYCLOAK_IMAGE="quay.io/keycloak/keycloak:25.0.6"
ZIPKIN_IMAGE="openzipkin/zipkin:2.26"
REDIS_IMAGE="redis:7.2-alpine"
NGINX_IMAGE="nginx:1.25-alpine"
HAPROXY_IMAGE="haproxy:2.8-alpine"
PROMETHEUS_IMAGE="prom/prometheus:latest"
GRAFANA_IMAGE="grafana/grafana:10.2.0"

# Services avec ports
SERVICES=("config-server" "eureka-server" "api-gateway" "video-core" "video-analyzer" "video-storage")
declare -A SERVICE_PORTS=(
  ["config-server"]=8888
  ["eureka-server"]=8761
  ["api-gateway"]=8084
  ["video-core"]=8085
  ["video-analyzer"]=8082
  ["video-storage"]=8083
)

# 🎛️ Arguments
parse_arguments() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --platform-name) PLATFORM_NAME="$2"; shift ;;
      --group-id) GROUP_ID="$2"; shift ;;
      --java-version) JAVA_VERSION="$2"; shift ;;
      --springboot-version) SPRINGBOOT_VERSION="$2"; shift ;;
      --init-config-repo) INIT_CONFIG_REPO=true; INIT_REPO_PATH="$2"; shift ;;
      --force) FORCE=true ;;
      --help) show_usage ;;
      *) error "Argument inconnu $1"; exit 1 ;;
    esac
    shift
  done
}

# 📋 Aide
show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --platform-name NAME    Nom de la plateforme (défaut: $PLATFORM_NAME)
  --group-id ID           Group ID Maven (défaut: $GROUP_ID)
  --java-version VERSION  Version Java (défaut: $JAVA_VERSION)
  --springboot-version V  Version Spring Boot (défaut: $SPRINGBOOT_VERSION)
  --init-config-repo PATH Initialiser le dépôt de configuration
  --force                 Forcer la recréation de la plateforme
  --help                  Afficher cette aide

Exemples:
  $0 --platform-name my-platform --group-id com.example --java-version 17
  $0 --init-config-repo \$HOME/my-config-repo --force
EOF
  exit 0
}

# Fonction pour vérifier les prérequis
check_prerequisites() {
  if [ -d "$PLATFORM_NAME" ] && [ "$FORCE" = false ]; then
    error "Le dossier $PLATFORM_NAME existe déjà. Utilisez --force pour écraser."
    exit 1
  fi

  if ! command -v java &> /dev/null; then
    error "Java n'est pas installé"
    exit 1
  fi
}

# Fonction pour créer la structure du projet
create_project_structure() {
  log "🚀 Génération de la plateforme $PLATFORM_NAME..."
  
  if [ "$FORCE" = true ] && [ -d "$PLATFORM_NAME" ]; then
    log "♻️ Écrasement du dossier existant..."
    rm -rf "$PLATFORM_NAME"
  fi
  
  mkdir -p "$PLATFORM_NAME"
  
  # Créer les fichiers de projet
  create_gitignore
  generate_project_files
  generate_docker_compose
  create_deploy_script
  # create_config_repo
  create_infrastructure_configs
}

# Fonction pour créer le .gitignore
create_gitignore() {
  cat > "$PLATFORM_NAME/.gitignore" <<EOF
# IDE
.idea/
*.iml
*.ipr
*.iws
.vscode/
.classpath
.project
.settings/
bin/
build/
target/

# Docker
docker-compose.override.yml

# Logs
*.log
logs/

# Autres
*.swp
*.swo
.DS_Store
.env
*.bak
*.tmp

# Configuration locale
/config-repo/
EOF
  success "Fichier .gitignore créé"
}

# 📂 Initialisation du dépôt de configuration
init_config_repo() {
  local repo_path="${1:-$INIT_REPO_PATH}"
  log "📂 Initialisation du dépôt de configuration: $repo_path"
  
  mkdir -p "$repo_path"
  
  if [[ -d "$repo_path/.git" ]]; then
    warn "Dépôt de configuration existe déjà: $repo_path"
    return
  fi
  
  cd "$repo_path" || exit 1
  git init
  
  # Fichiers de configuration de base
  for SERVICE in "${SERVICES[@]}"; do
    generate_config_repo_file "$SERVICE" "${SERVICE_PORTS[$SERVICE]}" "$repo_path"
  done
  
  git add .
  git config user.email "generator@smartvision"
  git config user.name "SmartVision Generator"
  git commit -m "Initial commit: Configuration des microservices"
  git branch -M main
  
  success "Dépôt de configuration initialisé: $repo_path"
  cd - > /dev/null
}

config_server_app_yml(){ cat <<YML
server:
  port: 8888
spring:
  application:
    name: config-server
  cloud:
    config:
      server:
        git:
          uri: file:$REPO_PATH
          clone-on-start: true
          force-pull: true
          default-label: \${CONFIG_REPO_BRANCH:main}
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/smartvision
management:
  endpoints:
    web:
      exposure:
        include: "*"
  tracing:
    sampling:
      probability: 1.0
YML
}

config_repo_gateway(){ cat <<YML
server:
  port: 8084
spring:
  application:
    name: api-gateway
  cloud:
    gateway:
      discovery:
        locator:
          enabled: true
          lower-case-service-id: true
      routes:
        - id: video-core
          uri: lb://video-core
          predicates: [ Path=/core/** ]
          filters: [ StripPrefix=1, RequestRateLimiter=10, 2, SECONDS ]
        - id: video-storage
          uri: lb://video-storage
          predicates: [ Path=/storage/** ]
          filters: [ StripPrefix=1, RequestRateLimiter=5, 1, SECONDS ]
        - id: video-analyzer
          uri: lb://video-analyzer
          predicates: [ Path=/analyzer/** ]
          filters: [ StripPrefix=1, RequestRateLimiter=3, 1, SECONDS ]
      httpclient:
        connect-timeout: 1000
        response-timeout: 5s
      default-filters:
        - DedupeResponseHeader=Access-Control-Allow-Credentials Access-Control-Allow-Origin
        - name: CircuitBreaker
          args:
            name: videoServices
            fallbackUri: forward:/fallback
        - name: RequestRateLimiter
          args:
            redis-rate-limiter.replenishRate: 10
            redis-rate-limiter.burstCapacity: 20
        - name: Retry
          args:
            retries: 3
            series: SERVER_ERROR
            methods: GET,POST
            backoff:
              firstBackoff: 10ms
              maxBackoff: 50ms
              factor: 2
              basedOnPreviousValue: false
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/smartvision
  data:
    redis:
      host: redis
      port: 6379
  redis:
    rate-limiter:
      enabled: true
      replenish-rate: 10
      burst-capacity: 20

eureka:
  client:
    register-with-eureka: true
    fetch-registry: true
    service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}

logging:
  level:
    org.springframework.cloud: DEBUG
    com.netflix: DEBUG

management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
    metrics:
      enabled: true
    refresh:
      enabled: true
    loggers:
      enabled: true
  tracing:
    sampling:
      probability: 1.0
  zipkin:
    tracing:
      endpoint: http://zipkin:9411/api/v2/spans
resilience4j:
  circuitbreaker:
    instances:
      videoServices:
        registerHealthIndicator: true
        slidingWindowSize: 10
        minimumNumberOfCalls: 5
        waitDurationInOpenState: 10000
        failureRateThreshold: 50
        permittedNumberOfCallsInHalfOpenState: 3
        slidingWindowType: COUNT_BASED
  timelimiter:
    instances:
      videoServices:
        timeoutDuration: 2s
YML
}

config_repo_eureka(){ cat <<YML
server:
  port: 8761
spring:
  application:
    name: eureka-server
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/smartvision
management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
eureka:
  client:
    register-with-eureka: false
    fetch-registry: false
	service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}
  instance:
    hostname: eureka-server
    prefer-ip-address: true
YML
}

config_repo_storage(){ cat <<YML
server:
  port: 8083
spring:
  application:
    name: video-storage
  data:
    mongodb:
      uri: mongodb://mongo:27017/smartvideo
      auto-index-creation: true
    redis:
      host: redis
      port: 6379
  cache:
    type: redis
    redis:
      time-to-live: 300000
      cache-null-values: false
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/smartvision

eureka:
  client:
    register-with-eureka: true
    fetch-registry: true
    service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}

management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
    refresh:
      enabled: true
    loggers:
      enabled: true
  tracing:
    sampling:
      probability: 1.0
logging:
  level:
    org.springframework.data.mongodb: DEBUG
    com.mongodb: WARN
YML
}

config_repo_core(){ cat <<YML
server:
  port: 8085
spring:
  application:
    name: video-core
  data:
    redis:
      host: redis
      port: 6379
  cache:
    type: redis
    redis:
      time-to-live: 60000
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/smartvision

eureka:
  client:
    register-with-eureka: true
    fetch-registry: true
    service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}

management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
    refresh:
      enabled: true
    loggers:
      enabled: true
  tracing:
    sampling:
      probability: 1.0
resilience4j:
  circuitbreaker:
    instances:
      storageService:
        registerHealthIndicator: true
        slidingWindowSize: 10
        minimumNumberOfCalls: 5

logging:
  level:
    org.springframework.data.mongodb: DEBUG
    com.mongodb: WARN
YML
}

config_repo_analyzer(){ cat <<YML
server:
  port: 8082
spring:
  application:
    name: video-analyzer
  data:
    redis:
      host: redis
      port: 6379
  cache:
    type: redis
    redis:
      time-to-live: 300000
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: http://keycloak:8080/realms/smartvision
  tensorflow:
    model-path: /app/models
management:
  endpoints:
    web:
      exposure:
        include: "*"
  endpoint:
    health:
      show-details: always
    refresh:
      enabled: true
    loggers:
      enabled: true
  tracing:
    sampling:
      probability: 1.0

eureka:
  client:
    register-with-eureka: true
    fetch-registry: true
    service-url:
      defaultZone: \${EUREKA_DEFAULTZONE:http://localhost:8761/eureka/}

logging:
  level:
    org.springframework.data.mongodb: DEBUG
    com.mongodb: WARN
YML
}

# 📄 Génération des fichiers de configuration pour le dépôt
generate_config_repo_file() {
  local SERVICE_NAME="$1"
  local SERVICE_PORT="$2"
  local REPO_PATH="$3"

  case "$SERVICE_NAME" in
    "config-server")
  config_server_app_yml > "$REPO_PATH/config-server.yml"     
      ;;
    "eureka-server")
      config_repo_eureka > "$REPO_PATH/eureka-server.yml"
      ;;
    *)
	if [[ "$SERVICE_NAME" == "api-gateway" ]]; then
	   config_repo_gateway > "$REPO_PATH/api-gateway.yml"
	fi
    if [[ "$SERVICE_NAME" == "video-storage" ]]; then
	   config_repo_storage > "$REPO_PATH/video-storage.yml"
	fi
	if [[ "$SERVICE_NAME" == "video-core" ]]; then
	   config_repo_core > "$REPO_PATH/video-core.yml"
	fi
	if [[ "$SERVICE_NAME" == "video-analyzer" ]]; then
	   config_repo_analyzer > "$REPO_PATH/video-analyzer.yml"
	fi
      ;;
  esac
}


java_storage_entity(){ 
  local SERVICE_NAME="$1"
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  cat <<JAVA
package $GROUP_ID.$PACKAGE_SAFE.model;

import lombok.*;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.time.Instant;

@Document("detection_metadata")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DetectionMetadata {
  @Id
  private String id;
  private String source;
  private String label;
  private double confidence;
  private Instant ts;
  private String cameraId;
  private String location;
}
JAVA
}

java_storage_repo(){ 
  local SERVICE_NAME="$1"
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  cat <<JAVA
package $GROUP_ID.$PACKAGE_SAFE.repo;

import $GROUP_ID.$PACKAGE_SAFE.model.DetectionMetadata;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import java.time.Instant;
import java.util.List;

public interface DetectionMetadataRepository extends MongoRepository<DetectionMetadata, String> {
  Page<DetectionMetadata> findByCameraId(String cameraId, Pageable pageable);
  List<DetectionMetadata> findByTsBetween(Instant start, Instant end);
  Long countByLabel(String label);
}
JAVA
}

java_storage_controller(){ 
  local SERVICE_NAME="$1"
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  cat <<JAVA
package $GROUP_ID.$PACKAGE_SAFE.api;

import $GROUP_ID.$PACKAGE_SAFE.model.DetectionMetadata;
import $GROUP_ID.$PACKAGE_SAFE.repo.DetectionMetadataRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;

@RestController
@RequestMapping("/api/detections")
@RequiredArgsConstructor
public class DetectionController {
  private final DetectionMetadataRepository repo;

  @PostMapping
  @ResponseStatus(HttpStatus.CREATED)
  public DetectionMetadata save(@RequestBody DetectionMetadata m){ return repo.save(m); }

  @GetMapping("/camera/{cameraId}")
  public Page<DetectionMetadata> getByCamera(@PathVariable String cameraId, Pageable pageable) {
    return repo.findByCameraId(cameraId, pageable);
  }

  @GetMapping("/stats/label/{label}")
  public Long countByLabel(@PathVariable String label) {
    return repo.countByLabel(label);
  }
}
JAVA
}

java_sample_controller(){ 
  local SERVICE_NAME="$1"
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  cat <<JAVA
package $GROUP_ID.$PACKAGE_SAFE.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {
  @GetMapping("/api/hello")
  public String hello(){ return "Hello from __SERVICE__"; }
}
JAVA
}

java_test_smoke(){ 
  local SERVICE_NAME="$1"
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  cat <<JAVA
package $GROUP_ID.$PACKAGE_SAFE.test;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ContextLoadsTest { @Test void contextLoads(){} }
JAVA
}

storage_bootstrap_test(){ cat <<'YML'
spring:
  cloud:
    config:
      enabled: false
  data:
    mongodb:
      # rien à définir, Boot détecte l’embedded
      spring.mongodb.embedded.version: 4.0.2

eureka:
  client:
    enabled: false
YML
}

java_test_controller(){ 
  local SERVICE_NAME="$1"
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  cat <<JAVA
package $GROUP_ID.$PACKAGE_SAFE.api;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
@AutoConfigureMockMvc
class HelloControllerTest {
  @Autowired MockMvc mvc;
  @Test void hello_is_ok() throws Exception { mvc.perform(get("/api/hello")).andExpect(status().isOk()); }
}
JAVA
}

realm_json(){ cat <<'JSON'
{
  "realm": "smartvision",
  "enabled": true,
  "users": [
    {
      "username": "admin",
      "enabled": true,
      "email": "admin@smartvision.com",
      "credentials": [
        {
          "type": "password",
          "value": "admin123",
          "temporary": false
        }
      ],
      "realmRoles": ["admin", "user"]
    },
    {
      "username": "user",
      "enabled": true,
      "email": "user@smartvision.com",
      "credentials": [
        {
          "type": "password",
          "value": "user123",
          "temporary": false
        }
      ],
      "realmRoles": ["user"]
    }
  ],
  "clients": [
    {
      "clientId": "api-gateway",
      "publicClient": true,
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": true,
      "redirectUris": ["http://localhost:8084/*", "http://localhost:8080/*"],
      "webOrigins": ["*"],
      "attributes": {
        "pkce.code.challenge.method": "S256"
      }
    },
    {
      "clientId": "monitoring",
      "publicClient": true,
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": true,
      "redirectUris": ["http://localhost:3000/*", "http://localhost:9090/*"],
      "webOrigins": ["*"]
    }
  ],
  "roles": {
    "realm": [
      {
        "name": "admin",
        "description": "Administrator role"
      },
      {
        "name": "user",
        "description": "User role"
      },
      {
        "name": "viewer",
        "description": "Read-only access"
      }
    ]
  }
}
JSON
}

nginx_conf(){ cat <<'NGINX'
events {
    worker_connections 1024;
}

http {
    upstream api_gateway {
        server api-gateway:8084;
        server api-gateway:8085 backup;
    }

    upstream monitoring {
        server grafana:3000;
        server prometheus:9090;
    }

    server {
        listen 80;
        server_name localhost;

        # Security headers
        add_header X-Frame-Options DENY always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

        # API Gateway
        location /api/ {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Rate limiting
            limit_req zone=api burst=20 nodelay;
            limit_req_status 429;
        }

        # Monitoring
        location /monitoring/ {
            proxy_pass http://monitoring/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Health checks
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }

    # Rate limiting zone
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
}
NGINX
}

haproxy_cfg(){ cat <<'HAPROXY'
global
    daemon
    maxconn 256

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option forwardfor
    option http-server-close

frontend http_in
    bind *:80
    default_backend services

backend services
    balance roundrobin
    server api-gateway1 api-gateway:8084 check
    server api-gateway2 api-gateway:8085 check backup

    # Health check
    option httpchk GET /actuator/health
    http-check expect status 200

frontend stats
    bind *:1936
    stats enable
    stats uri /
    stats hide-version
    stats auth admin:admin
HAPROXY
}

prometheus_yml(){ cat <<'YML'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'spring-boot'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: 
        - 'api-gateway:8084'
        - 'video-core:8085'
        - 'video-storage:8083'
        - 'video-analyzer:8082'
        - 'config-server:8888'
        - 'eureka-server:8761'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '(.*):\d+'
        replacement: '${1}'

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:9121']

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - '/etc/prometheus/alert-rules.yml'
YML
}

grafana_datasources(){ cat <<'JSON'
{
  "apiVersion": 1,
  "datasources": [
    {
      "name": "Prometheus",
      "type": "prometheus",
      "url": "http://prometheus:9090",
      "access": "proxy",
      "isDefault": true,
      "jsonData": {
        "timeInterval": "15s"
      }
    },
    {
      "name": "Loki",
      "type": "loki",
      "url": "http://loki:3100",
      "access": "proxy"
    }
  ]
}
JSON
}

# Infrastructure configs
create_infrastructure_configs(){
  # Nginx
  mkdir -p "$PLATFORM_NAME/nginx"
  nginx_conf > "$PLATFORM_NAME/nginx/nginx.conf"

  # HAProxy
  mkdir -p "$PLATFORM_NAME/haproxy"
  haproxy_cfg > "$PLATFORM_NAME/haproxy/haproxy.cfg"

  # Prometheus
  mkdir -p "$PLATFORM_NAME/prometheus"
  prometheus_yml > "$PLATFORM_NAME/prometheus/prometheus.yml"

  # Grafana
  mkdir -p "$PLATFORM_NAME/grafana/datasources"
  grafana_datasources > "$PLATFORM_NAME/grafana/datasources/datasources.yml"

  # Keycloak
  mkdir -p "$PLATFORM_NAME/keycloak"
  realm_json > "$PLATFORM_NAME/keycloak/realm-export.json"
}

# 📂 Création d'un microservice
create_service() {
  local SERVICE_NAME="$1"
  local CAMEL_CASE_NAME=$(to_camel_case "$SERVICE_NAME")
  local PACKAGE_SAFE=$(package_format "$SERVICE_NAME")
  local SERVICE_DIR="$PLATFORM_NAME/$SERVICE_NAME"

  log "Création du service: $SERVICE_NAME"

  if [[ "$FORCE" == false && -d "$SERVICE_DIR" ]]; then
    warn "Service $SERVICE_NAME existe déjà. Utilisez --force pour écraser."
    return
  fi

  if [[ "$FORCE" == true && -d "$SERVICE_DIR" ]]; then
    rm -rf "$SERVICE_DIR"
  fi

  mkdir -p "$SERVICE_DIR/src/main/java" "$SERVICE_DIR/src/main/resources"
  mkdir -p "$SERVICE_DIR/src/test/java" "$SERVICE_DIR/src/test/resources"

  # Déterminer les dépendances spécifiques
  local DEPENDENCIES=""
  local IMPORTS=""
  local ANNOTATION="@SpringBootApplication"
  local BOOTSTRAP_DEPENDENCY=""
  local VALIDATION_DEPENDENCY="<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-validation</artifactId>
    </dependency>"
  local CACHE_DEPENDENCY="<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-cache</artifactId>
    </dependency>
    <dependency>
      <groupId>com.github.ben-manes.caffeine</groupId>
      <artifactId>caffeine</artifactId>
    </dependency>"

  case "$SERVICE_NAME" in
    "config-server")
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-config-server</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.config.server.EnableConfigServer;"
      ANNOTATION='@EnableConfigServer
@SpringBootApplication'
      # Config Server n'a pas besoin de bootstrap
      ;;

    "eureka-server")
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-server</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.netflix.eureka.server.EnableEurekaServer;"
      ANNOTATION='@EnableEurekaServer
@SpringBootApplication'
      BOOTSTRAP_DEPENDENCY="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-bootstrap</artifactId>
    </dependency>"
      ;;

    "api-gateway")
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-gateway</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-oauth2-client</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-redis</artifactId>
    </dependency>
    <dependency>
      <groupId>io.github.resilience4j</groupId>
      <artifactId>resilience4j-spring-boot2</artifactId>
    </dependency>
    <dependency>
      <groupId>io.github.resilience4j</groupId>
      <artifactId>resilience4j-all</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.client.discovery.EnableDiscoveryClient;"
      ANNOTATION='@EnableDiscoveryClient
@SpringBootApplication'
      BOOTSTRAP_DEPENDENCY="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-bootstrap</artifactId>
    </dependency>"
      ;;
   
   
   "video-storage")
	  DEPENDENCIES="<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-mongodb</artifactId>
    </dependency>
	<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>de.flapdoodle.embed</groupId>
      <artifactId>de.flapdoodle.embed.mongo</artifactId>
      <version>\${flapdoodle.version}</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-data-redis</artifactId>
    </dependency>"
       ;;
   
    "video-analyzer")   
       DEPENDENCIES="<dependency>
       <groupId>org.springframework.boot</groupId>
       <artifactId>spring-boot-starter-data-redis</artifactId>
    </dependency>
	<dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
      <groupId>org.tensorflow</groupId>
      <artifactId>tensorflow-core-api</artifactId>
      <version>\${tansorflow.version}</version>
    </dependency>"
	;;
    *)
      # Services vidéo
      DEPENDENCIES="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-web</artifactId>
    </dependency>"
      IMPORTS="import org.springframework.cloud.client.discovery.EnableDiscoveryClient;"
      ANNOTATION='@EnableDiscoveryClient
@SpringBootApplication'
      BOOTSTRAP_DEPENDENCY="<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-config</artifactId>
    </dependency>
	<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-netflix-eureka-client</artifactId>
    </dependency>
    <dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-bootstrap</artifactId>
    </dependency>
	<dependency>
      <groupId>org.springframework.cloud</groupId>
      <artifactId>spring-cloud-starter-loadbalancer</artifactId>
    </dependency>"
      ;;
  esac

  # pom.xml
  cat > "$SERVICE_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>$SPRINGBOOT_VERSION</version>
  </parent>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$SERVICE_NAME</artifactId>
  <version>0.0.1-SNAPSHOT</version>
  <properties>
    <java.version>$JAVA_VERSION</java.version>
    <spring-cloud.version>$SPRINGCLOUD_VERSION</spring-cloud.version>
	<flapdoodle.version>4.13.0</flapdoodle.version>
	<jacoco.version>0.8.10</jacoco.version>
	<tansorflow.version>0.5.0</tansorflow.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-actuator</artifactId>
    </dependency>
	<dependency>
      <groupId>io.micrometer</groupId>
      <artifactId>micrometer-registry-prometheus</artifactId>
    </dependency>
    $DEPENDENCIES
    $BOOTSTRAP_DEPENDENCY
    $VALIDATION_DEPENDENCY
    $CACHE_DEPENDENCY
    <dependency>
      <groupId>org.projectlombok</groupId>
      <artifactId>lombok</artifactId>
      <optional>true</optional>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId>
      <artifactId>spring-boot-starter-test</artifactId>
      <scope>test</scope>
    </dependency>
  </dependencies>
  <dependencyManagement>
    <dependencies>
      <dependency>
        <groupId>org.springframework.cloud</groupId>
        <artifactId>spring-cloud-dependencies</artifactId>
        <version>\${spring-cloud.version}</version>
        <type>pom</type>
        <scope>import</scope>
      </dependency>
    </dependencies>
  </dependencyManagement>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
	  <plugin>
        <groupId>org.jacoco</groupId>
        <artifactId>jacoco-maven-plugin</artifactId>
        <version>\${jacoco.version}</version>
        <executions>
          <execution>
            <goals>
              <goal>prepare-agent</goal>
            </goals>
          </execution>
          <execution>
            <id>report</id>
            <phase>test</phase>
            <goals>
              <goal>report</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
EOF

  # Application.java
  local PACKAGE_DIR=$(echo "$GROUP_ID" | sed 's/\./\//g')/$PACKAGE_SAFE
  mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR"
  mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/api"

  cat > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/${CAMEL_CASE_NAME}Application.java" <<EOF
package $GROUP_ID.$PACKAGE_SAFE;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
$IMPORTS
import org.springframework.context.annotation.Profile;

//@Profile("!test")
$ANNOTATION
public class ${CAMEL_CASE_NAME}Application {
    public static void main(String[] args) {
        SpringApplication.run(${CAMEL_CASE_NAME}Application.class, args);
    }
}
EOF
  
  if [[ "$SERVICE_NAME" == "eureka-server" ]]; then
      # générer HelloController + test MockMvc
	  cat > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/${CAMEL_CASE_NAME}Application.java" <<EOF
package $GROUP_ID.$PACKAGE_SAFE;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
$IMPORTS
import org.springframework.context.annotation.Profile;

@Profile("!test")
$ANNOTATION
public class ${CAMEL_CASE_NAME}Application {
    public static void main(String[] args) {
        SpringApplication.run(${CAMEL_CASE_NAME}Application.class, args);
    }
}
EOF
  fi    
  
  if [[ "$SERVICE_NAME" != "config-server" && "$SERVICE_NAME" != "eureka-server" && "$SERVICE_NAME" != "api-gateway" ]]; then
      # générer HelloController + test MockMvc
	  java_sample_controller "$SERVICE_NAME" > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/api/HelloController.java"
  fi    
  
  
  if [[ "$SERVICE_NAME" == "video-storage" ]]; then
      mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/model"
	  mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/repo"
	  mkdir -p "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/controller"
	  
	  java_storage_entity "$SERVICE_NAME" > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/model/DetectionMetadata.java"
	  java_storage_repo "$SERVICE_NAME" > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/repo/DetectionMetadataRepository.java"
	  java_storage_controller "$SERVICE_NAME" > "$SERVICE_DIR/src/main/java/$PACKAGE_DIR/controller/DetectionController.java"
  fi
  # Fichiers de configuration
  generate_resource_files "$SERVICE_NAME" "$SERVICE_DIR" "${SERVICE_PORTS[$SERVICE_NAME]}"

  # Tests unitaires
  generate_unit_tests "$SERVICE_NAME" "$SERVICE_DIR" "$CAMEL_CASE_NAME" "$PACKAGE_SAFE"

  # Dockerfile
  cat > "$SERVICE_DIR/Dockerfile" <<EOF
FROM eclipse-temurin:$JAVA_VERSION-jdk-jammy
VOLUME /tmp
COPY "target/$SERVICE_NAME-0.0.1-SNAPSHOT.jar" app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
EOF

  success "Service $SERVICE_NAME créé"
}

# 📄 Génération des fichiers de ressources
generate_resource_files() {
  local SERVICE_NAME="$1"
  local SERVICE_DIR="$2"
  local SERVICE_PORT="$3"

  if [[ "$SERVICE_NAME" == "config-server" ]]; then
    # Config Server - application.yml seulement
    cat > "$SERVICE_DIR/src/main/resources/application.yml" <<EOF
server:
  port: $SERVICE_PORT
spring:
  application:
    name: config-server
  cloud:
    config:
      server:
        git:
          uri: file:$INIT_REPO_PATH
          clone-on-start: true
          force-pull: true
          default-label: \${CONFIG_REPO_BRANCH:main}

logging:
  level:
    org.springframework.cloud: DEBUG
    com.netflix: DEBUG
EOF

    # application-test.yml pour les tests
    cat > "$SERVICE_DIR/src/test/resources/application-test.yml" <<EOF
spring:
  cloud:
    config:
      enabled: false
eureka:
  client:
    enabled: false
EOF

  else
    # Services clients - bootstrap.yml pour la config
    cat > "$SERVICE_DIR/src/main/resources/bootstrap.yml" <<EOF
spring:
  application:
    name: $SERVICE_NAME
  cloud:
    config:
      uri: \${CONFIG_URI:http://localhost:8888}
      fail-fast: true
EOF
   # bootstrap-test.yml pour désactiver config server pendant les tests
    cat > "$SERVICE_DIR/src/test/resources/bootstrap-test.yml" <<EOF
spring:
  cloud:
    config:
      enabled: false
eureka:
  client:
    enabled: false
EOF

    if [[ "$SERVICE_NAME" == "video-storage" ]]; then
	    storage_bootstrap_test >> "$SERVICE_DIR/src/test/resources/bootstrap-test.yml"
	fi

  fi
}

# 🧪 Génération des tests unitaires
generate_unit_tests() {
  local SERVICE_NAME="$1"
  local SERVICE_DIR="$2"
  local CAMEL_CASE_NAME="$3"
  local PACKAGE_SAFE="$4"
  local PACKAGE_DIR=$(echo "$GROUP_ID" | sed 's/\./\//g')/$PACKAGE_SAFE

  mkdir -p "$SERVICE_DIR/src/test/java/$PACKAGE_DIR"
  mkdir -p "$SERVICE_DIR/src/test/java/$PACKAGE_DIR/api"
  
  cat > "$SERVICE_DIR/src/test/java/$PACKAGE_DIR/${CAMEL_CASE_NAME}ApplicationTests.java" <<EOF
package $GROUP_ID.$PACKAGE_SAFE;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class ${CAMEL_CASE_NAME}ApplicationTests {
    @Test
    void contextLoads() {}
}
EOF
  
  java_test_smoke "$SERVICE_NAME" > "$SERVICE_DIR/src/test/java/$PACKAGE_DIR/ContextLoadsTest.java"
  if [[ "$SERVICE_NAME" != "config-server" && "$SERVICE_NAME" != "eureka-server" && "$SERVICE_NAME" != "api-gateway" ]]; then
      # générer HelloController + test MockMvc
	  java_test_controller "$SERVICE_NAME" > "$SERVICE_DIR/src/test/java/$PACKAGE_DIR/api/HelloControllerTest.java"
  fi    
  
}

# 🐳 Génération du docker-compose.yml
generate_docker_compose() {
  cat > "$PLATFORM_NAME/docker-compose.yml" <<EOF
services:
  # Infrastructure services
  nginx:
    image: $NGINX_IMAGE
    container_name: ${PLATFORM_NAME}-nginx
    ports: ["80:80"]
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - api-gateway
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 5s
      retries: 3

  haproxy:
    image: $HAPROXY_IMAGE
    container_name: ${PLATFORM_NAME}-haproxy
    ports: ["8087:80", "1936:1936"]
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - api-gateway

  redis:
    image: $REDIS_IMAGE
    container_name: ${PLATFORM_NAME}-redis
    ports: ["6379:6379"]
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  zipkin:
    image: $ZIPKIN_IMAGE
    container_name: ${PLATFORM_NAME}-zipkin
    ports: ["9411:9411"]
    environment:
      - STORAGE_TYPE=mem

  keycloak:
    image: $KEYCLOAK_IMAGE
    container_name: ${PLATFORM_NAME}-keycloak
    command: ["start-dev", "--import-realm"]
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin123
      KC_HTTP_ENABLED: "true"
      KC_HOSTNAME_STRICT: "false"
    volumes:
      - ./keycloak/realm-export.json:/opt/keycloak/data/import/realm-export.json:ro
    ports: ["8086:8080"]
 
  mongodb:
    image: $MONGO_IMAGE
    container_name: mongodb
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_DATABASE: smartvideo
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: ["CMD", "mongo", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
  
  # Monitoring stack
  prometheus:
    image: $PROMETHEUS_IMAGE
    container_name: ${PLATFORM_NAME}-prometheus
    ports: ["9090:9090"]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9090/-/healthy"]
      interval: 10s
      timeout: 5s
      retries: 3

  grafana:
    image: $GRAFANA_IMAGE
    container_name: ${PLATFORM_NAME}-grafana
    ports: ["3000:3000"]
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_USERS_ALLOW_SIGN_UP: "false"
    volumes:
      - ./grafana/datasources:/etc/grafana/provisioning/datasources
      - grafana_data:/var/lib/grafana
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      
  config-server:
    build: ./config-server
    container_name: ${PLATFORM_NAME}-config-server
    ports:
      - "8888:8888"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8888/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - smartvision-net
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    environment:
      - HOME=${HOME}
      - CONFIG_REPO_BRANCH=\${CONFIG_REPO_BRANCH:-main}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}

  eureka-server:
    build: ./eureka-server
    hostname: eureka-server
    container_name: ${PLATFORM_NAME}-eureka-server
    ports:
      - "8761:8761"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8761/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    networks:
      - smartvision-net
    environment:
      - HOME=${HOME}
      - EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE=\${EUREKA_DEFAULTZONE:-http://eureka-server:8761/eureka/}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}
      - SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI=\${ISSUER_URI:-http://keycloak:8080/realms/smartvision}
    depends_on:
      config-server:
        condition: service_healthy
      redis:
        condition: service_healthy

EOF

  # Ajouter les autres services
  for SERVICE in "api-gateway" "video-core" "video-analyzer" "video-storage"; do
    PORT=${SERVICE_PORTS[$SERVICE]}
	if [[ "$SERVICE" != "video-storage" ]]; then
       cat >> "$PLATFORM_NAME/docker-compose.yml" <<EOF

  $SERVICE:
    build: ./$SERVICE
    container_name: ${PLATFORM_NAME}-$SERVICE
    ports:
      - "$PORT:$PORT"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:$PORT/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - smartvision-net
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    environment:
      - HOME=${HOME}
      - EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE=\${EUREKA_DEFAULTZONE:-http://eureka-server:8761/eureka/}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}
      - SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI=\${ISSUER_URI:-http://keycloak:8080/realms/smartvision}
    depends_on:
      config-server:
        condition: service_healthy
      eureka-server:
        condition: service_healthy
      keycloak:
        condition: service_started
      zipkin:
        condition: service_started
EOF
  else
    cat >> "$PLATFORM_NAME/docker-compose.yml" <<EOF
  video-storage:
    build: ./video-storage
    container_name: ${PLATFORM_NAME}-video-storage
    ports:
      - "8083:8083"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8083/actuator/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - smartvision-net
    volumes:
      - ${INIT_REPO_PATH}:${INIT_REPO_PATH}
    environment:
      - HOME=${HOME}
      - EUREKA_CLIENT_SERVICE_URL_DEFAULTZONE=\${EUREKA_DEFAULTZONE:-http://eureka-server:8761/eureka/}
      - SPRING_CLOUD_CONFIG_URI=\${CONFIG_URI:-http://config-server:8888}
      - SPRING_PROFILES_ACTIVE=\${SPRING_PROFILES_ACTIVE:-docker}
      - SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI=\${ISSUER_URI:-http://keycloak:8080/realms/smartvision}
    depends_on:
      config-server:
        condition: service_healthy
      eureka-server:
        condition: service_healthy
      mongodb:
        condition: service_healthy
      keycloak:
        condition: service_started
      zipkin:
        condition: service_started
EOF
  fi	
  done
  
  cat >> "$PLATFORM_NAME/docker-compose.yml" <<EOF
volumes:
  mongo_data:
    driver: local
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
networks:
  smartvision-net:
    driver: bridge
EOF
}

# 📋 Génération des fichiers de projet
generate_project_files() {
  # .env.example
  cat > "$PLATFORM_NAME/.env.example" <<EOF
# Configuration Docker Compose
CONFIG_REPO_BRANCH=main
SPRING_PROFILES_ACTIVE=docker
EOF

  # README.md
  cat > "$PLATFORM_NAME/README.md" <<EOF
# $PLATFORM_NAME

Plateforme microservices SmartVision

## Services et Ports

| Service | Port |
|---------|------|
EOF

  for SERVICE in "${SERVICES[@]}"; do
    echo "| $SERVICE | ${SERVICE_PORTS[$SERVICE]} |" >> "$PLATFORM_NAME/README.md"
  done

  cat >> "$PLATFORM_NAME/README.md" <<EOF
## Infrastructure Services
- Nginx Load Balancer: 80
- HAProxy: 81 (HTTP), 1936 (Stats)
- Keycloak (OAuth2): 8080
- Redis: 6379
- MongoDB: 27017
- Zipkin (Tracing): 9411
- Prometheus (Metrics): 9090
- Grafana (Dashboards): 3000

## Security Features
- OAuth2/JWT Authentication
- Role-Based Access Control (RBAC)
- TLS Encryption
- Rate Limiting
- Circuit Breakers
- Request Tracing

## Monitoring
- Prometheus for metrics collection
- Grafana for visualization
- Zipkin for distributed tracing
- Health checks and metrics endpoints

## Démarrage

1. Copier le fichier d'environnement: \`cp .env.example .env\`
2. Construire les images: \`docker-compose build\`
3. Démarrer les services: \`docker-compose up -d\`

# Access services
http://localhost:80          # Nginx Load Balancer
http://localhost:8080        # Keycloak Admin Console
http://localhost:3000        # Grafana Dashboards
http://localhost:9090        # Prometheus
http://localhost:9411        # Zipkin Tracing
\`\`\`

## Default Credentials
- Keycloak Admin: admin/admin123
- Grafana Admin: admin/admin
- HAProxy Stats: admin/admin
## Tests

\`\`\`bash
# Lancer les tests avec le profil test
mvn test -Dspring.profiles.active=test
\`\`\`
EOF
}

create_deploy_script(){
  cat > "$PLATFORM_NAME/deploy-smartvision.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
CMD="${1:-}"; shift || true

case "$CMD" in
  build)
    echo "🔨 Building jars and Docker images..."
    for d in config-server eureka-server api-gateway video-core video-analyzer video-storage; do
      echo "➡️  Building $d..."
      (cd "$d" && mvn -q -DskipTests=${SKIP_TESTS:-0} clean package)
    done
    docker compose build --pull
    echo "✅ Build completed successfully"
    ;;
  up)
    echo "🚀 Starting services..."
    docker compose up -d --remove-orphans
    echo "✅ Services started"
    echo "📊 Monitoring: http://localhost:3000"
    echo "🔐 Keycloak: http://localhost:8080"
    echo "📈 Prometheus: http://localhost:9090"
    echo "🔍 Zipkin: http://localhost:9411"
    echo "🌐 API Gateway: http://localhost:8084"
    ;;
  down)
    echo "🛑 Stopping services..."
    docker compose down -v --remove-orphans
    echo "✅ Services stopped"
    ;;
  logs)
    docker compose logs -f --tail=200 "$@"
    ;;
  restart)
    docker compose restart "$@"
    ;;
  status)
    docker compose ps
    ;;
  monitor)
    watch -n 5 'docker compose ps | grep -E "(Up|Exit)"'
    ;;
  update)
    git pull origin main
    ./deploy-smartvision.sh build
    ./deploy-smartvision.sh up
    ;;
  *)
    cat <<EOF
Usage: ./deploy-smartvision.sh [command]

Commands:
  build     - Build all services and Docker images
  up        - Start all services
  down      - Stop and remove all services
  logs      - Show service logs
  restart   - Restart specific services
  status    - Show service status
  monitor   - Monitor services in real-time
  update    - Update and redeploy platform

Environment variables:
  SKIP_TESTS - Set to 1 to skip tests during build
EOF
    ;;
esac
SH
  chmod +x "$PLATFORM_NAME/deploy-smartvision.sh"
}

# 🎯 Fonction principale
main() {
  log "Démarrage de la génération de la plateforme..."
  parse_arguments "$@"
  
  SPRINGCLOUD_VERSION=${SPRING_CLOUD_VERSIONS[$SPRINGBOOT_VERSION]}
  if [ -z "$SPRINGCLOUD_VERSION" ]; then
    error "Version Spring Cloud non trouvée pour Spring Boot $SPRINGBOOT_VERSION"
    exit 1
  fi
  
  check_prerequisites
  create_project_structure
  
  for SERVICE in "${SERVICES[@]}"; do
    create_service "$SERVICE"
  done
  
  success "Plateforme $PLATFORM_NAME générée avec succès!"
  
  if [ "$INIT_CONFIG_REPO" = true ]; then
    init_config_repo "$INIT_REPO_PATH"
  fi
}

main "$@"
