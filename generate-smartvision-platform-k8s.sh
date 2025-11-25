#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# SmartVision Platform — KUBERNETES GENERATOR (V1)
# Génère les manifests K8s pour :
#  - Namespace
#  - Config global (ConfigMap)
#  - Microservices Spring Boot (Deployments + Services)
#  - MongoDB, Redis
#  - Kafka + Zookeeper
#  - IA Python (consommateur Kafka)
#  - Keycloak, Zipkin, Prometheus, Grafana
#  - Ingress pour exposer API + monitoring
# ============================================================================

NAMESPACE="smartvision"
OUTPUT_DIR="k8s"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-smartvision}"  # ex: myregistry.com/smartvision
PLATFORM_NAME="smartvision-platform"

# Ports des services (alignés sur ton script actuel)
declare -A SERVICE_PORTS=(
  ["config-server"]=8888
  ["eureka-server"]=8761
  ["api-gateway"]=8084
  ["video-core"]=8085
  ["video-analyzer"]=8082
  ["video-storage"]=8083
)

# Topics Kafka (IA <-> microservices)
KAFKA_TOPIC_IN="video-events-in"
KAFKA_TOPIC_OUT="video-events-out"

log() { echo -e "📦 $1"; }

create_dirs() {
  mkdir -p "${OUTPUT_DIR}"/{base,infra,monitoring,ingress}
}

# ----------------------------------------------------------------------------
# Namespace
# ----------------------------------------------------------------------------
create_namespace() {
  cat > "${OUTPUT_DIR}/base/namespace.yml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
}

# ----------------------------------------------------------------------------
# ConfigMap global (valeurs utilisées par les microservices)
# ----------------------------------------------------------------------------
create_global_configmap() {
  cat > "${OUTPUT_DIR}/base/config-global.yml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: smartvision-common-env
  namespace: ${NAMESPACE}
data:
  CONFIG_URI: "http://config-server:8888"
  EUREKA_DEFAULTZONE: "http://eureka-server:8761/eureka/"
  ISSUER_URI: "http://keycloak:8080/realms/smartvision"
  ZIPKIN_ENDPOINT: "http://zipkin:9411/api/v2/spans"
  SPRING_PROFILES_ACTIVE: "docker"   # tu pourras créer un profil "k8s" si besoin
EOF
}

# ----------------------------------------------------------------------------
# Microservice Spring Boot : Deployment + Service
# ----------------------------------------------------------------------------
create_microservice() {
  local NAME="$1"
  local PORT="${SERVICE_PORTS[$NAME]}"
  local IMAGE="${DOCKER_REGISTRY}/${PLATFORM_NAME}-${NAME}:latest"

  cat > "${OUTPUT_DIR}/base/${NAME}-deployment.yml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      containers:
        - name: ${NAME}
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: ${PORT}
          env:
            - name: CONFIG_URI
              valueFrom:
                configMapKeyRef:
                  name: smartvision-common-env
                  key: CONFIG_URI
            - name: EUREKA_DEFAULTZONE
              valueFrom:
                configMapKeyRef:
                  name: smartvision-common-env
                  key: EUREKA_DEFAULTZONE
            - name: SPRING_SECURITY_OAUTH2_RESOURCESERVER_JWT_ISSUER_URI
              valueFrom:
                configMapKeyRef:
                  name: smartvision-common-env
                  key: ISSUER_URI
            - name: SPRING_PROFILES_ACTIVE
              valueFrom:
                configMapKeyRef:
                  name: smartvision-common-env
                  key: SPRING_PROFILES_ACTIVE
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: ${PORT}
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: ${PORT}
            initialDelaySeconds: 30
            periodSeconds: 20
          resources:
            requests:
              cpu: "200m"
              memory: "512Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
EOF

  cat > "${OUTPUT_DIR}/base/${NAME}-service.yml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${NAME}
spec:
  type: ClusterIP
  selector:
    app: ${NAME}
  ports:
    - name: http
      port: ${PORT}
      targetPort: ${PORT}
EOF
}

# ----------------------------------------------------------------------------
# MongoDB (pour video-storage)
# ----------------------------------------------------------------------------
create_mongodb() {
  cat > "${OUTPUT_DIR}/infra/mongodb.yml" <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongo-pvc
  namespace: ${NAMESPACE}
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
spec:
  selector:
    app: mongodb
  ports:
    - port: 27017
      targetPort: 27017
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
        - name: mongodb
          image: mongo:4.4
          ports:
            - containerPort: 27017
          volumeMounts:
            - name: mongo-data
              mountPath: /data/db
      volumes:
        - name: mongo-data
          persistentVolumeClaim:
            claimName: mongo-pvc
EOF
}

# ----------------------------------------------------------------------------
# Redis
# ----------------------------------------------------------------------------
create_redis() {
  cat > "${OUTPUT_DIR}/infra/redis.yml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7.2-alpine
          args: ["redis-server", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru"]
          ports:
            - containerPort: 6379
EOF
}

# ----------------------------------------------------------------------------
# Kafka + Zookeeper (simple cluster pour dev / prod light)
# ----------------------------------------------------------------------------
create_kafka() {
  cat > "${OUTPUT_DIR}/infra/kafka.yml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: zookeeper
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 2181
      targetPort: 2181
  selector:
    app: zookeeper
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zookeeper
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zookeeper
  template:
    metadata:
      labels:
        app: zookeeper
    spec:
      containers:
        - name: zookeeper
          image: bitnami/zookeeper:3.9
          env:
            - name: ALLOW_ANONYMOUS_LOGIN
              value: "yes"
          ports:
            - containerPort: 2181
---
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9092
      targetPort: 9092
  selector:
    app: kafka
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
        - name: kafka
          image: bitnami/kafka:3.7
          env:
            - name: KAFKA_CFG_ZOOKEEPER_CONNECT
              value: "zookeeper:2181"
            - name: ALLOW_PLAINTEXT_LISTENER
              value: "yes"
            - name: KAFKA_CFG_LISTENERS
              value: PLAINTEXT://:9092
            - name: KAFKA_CFG_ADVERTISED_LISTENERS
              value: PLAINTEXT://kafka:9092
          ports:
            - containerPort: 9092
EOF
}

# ----------------------------------------------------------------------------
# IA Python (consommateur / producteur Kafka)
# ----------------------------------------------------------------------------
create_ia_python() {
  cat > "${OUTPUT_DIR}/infra/ia-python.yml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ia-python
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ia-python
  template:
    metadata:
      labels:
        app: ia-python
    spec:
      containers:
        - name: ia-python
          image: ${DOCKER_REGISTRY}/smartvision-ia:latest
          imagePullPolicy: IfNotPresent
          env:
            - name: KAFKA_BOOTSTRAP_SERVERS
              value: "kafka:9092"
            - name: KAFKA_TOPIC_IN
              value: "${KAFKA_TOPIC_IN}"
            - name: KAFKA_TOPIC_OUT
              value: "${KAFKA_TOPIC_OUT}"
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "2"
              memory: "4Gi"
EOF
}

# ----------------------------------------------------------------------------
# Keycloak, Zipkin, Prometheus, Grafana
# ----------------------------------------------------------------------------
create_keycloak() {
  cat > "${OUTPUT_DIR}/infra/keycloak.yml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    app: keycloak
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:25.0.6
          args: ["start-dev", "--import-realm"]
          env:
            - name: KEYCLOAK_ADMIN
              value: "admin"
            - name: KEYCLOAK_ADMIN_PASSWORD
              value: "admin123"
          ports:
            - containerPort: 8080
EOF
}

create_zipkin() {
  cat > "${OUTPUT_DIR}/infra/zipkin.yml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: zipkin
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9411
      targetPort: 9411
  selector:
    app: zipkin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zipkin
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: zipkin
  template:
    metadata:
      labels:
        app: zipkin
    spec:
      containers:
        - name: zipkin
          image: openzipkin/zipkin:2.26
          ports:
            - containerPort: 9411
EOF
}

create_prometheus_grafana() {
  cat > "${OUTPUT_DIR}/monitoring/prometheus.yml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
  namespace: ${NAMESPACE}
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s

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
EOF

  cat >> "${OUTPUT_DIR}/monitoring/prometheus.yml" <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 9090
      targetPort: 9090
  selector:
    app: prometheus
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
        - name: prometheus
          image: prom/prometheus:latest
          args:
            - "--config.file=/etc/prometheus/prometheus.yml"
          ports:
            - containerPort: 9090
          volumeMounts:
            - name: config
              mountPath: /etc/prometheus
      volumes:
        - name: config
          configMap:
            name: prometheus-config
            items:
              - key: prometheus.yml
                path: prometheus.yml
EOF

  cat > "${OUTPUT_DIR}/monitoring/grafana.yml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  ports:
    - port: 3000
      targetPort: 3000
  selector:
    app: grafana
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:10.2.0
          env:
            - name: GF_SECURITY_ADMIN_PASSWORD
              value: "admin"
          ports:
            - containerPort: 3000
EOF
}

# ----------------------------------------------------------------------------
# Ingress (nécessite un Ingress Controller type nginx-ingress)
# ----------------------------------------------------------------------------
create_ingress() {
  cat > "${OUTPUT_DIR}/ingress/ingress.yml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: smartvision-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /\$2
spec:
  ingressClassName: nginx
  rules:
    - host: smartvision.local
      http:
        paths:
          - path: /api(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 8084
          - path: /grafana(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
          - path: /prometheus(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: prometheus
                port:
                  number: 9090
          - path: /zipkin(/|$)(.*)
            pathType: Prefix
            backend:
              service:
                name: zipkin
                port:
                  number: 9411
EOF
}

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------
main() {
  log "Génération des manifests Kubernetes dans ${OUTPUT_DIR}/ ..."
  create_dirs
  create_namespace
  create_global_configmap

  # Microservices Spring
  for svc in config-server eureka-server api-gateway video-core video-analyzer video-storage; do
    create_microservice "$svc"
  done

  # Infra + IA
  create_mongodb
  create_redis
  create_kafka
  create_ia_python
  create_keycloak
  create_zipkin
  create_prometheus_grafana
  create_ingress

  log "✅ Manifests générés. Déploiement possible avec :"
  echo "   kubectl apply -f ${OUTPUT_DIR}/base -f ${OUTPUT_DIR}/infra -f ${OUTPUT_DIR}/monitoring -f ${OUTPUT_DIR}/ingress"
}

main "$@"

