#!/usr/bin/env bash

set -euo pipefail

# ============================================================================
# SmartVision - Génération des manifestes Kubernetes (V2)
#   - Namespace
#   - Kafka (Strimzi)
#   - PostgreSQL
#   - MongoDB
#   - Microservices Spring Boot (video-core, video-storage, video-analyzer,
#     config-server, eureka-server, api-gateway)
#   - IA Python (ai-engine, consommation/production Kafka)
#   - Ingress Nginx pour api-gateway
#   - Observabilité : Prometheus, Grafana, Zipkin
#   - Auth : Keycloak (mode start-dev, à durcir pour la prod réelle)
# ============================================================================

NAMESPACE="smartvision-prod"
BASE_DIR="k8s"

# Images par défaut (à adapter avec ton registry)
IMAGE_VIDEO_CORE="registry.local/smartvision/video-core:latest"
IMAGE_VIDEO_STORAGE="registry.local/smartvision/video-storage:latest"
IMAGE_VIDEO_ANALYZER="registry.local/smartvision/video-analyzer:latest"   # Spring Boot
IMAGE_CONFIG_SERVER="registry.local/smartvision/config-server:latest"
IMAGE_EUREKA_SERVER="registry.local/smartvision/eureka-server:latest"
IMAGE_API_GATEWAY="registry.local/smartvision/api-gateway:latest"

# IA Python
IMAGE_AI_ENGINE="registry.local/smartvision/ai-engine:latest"             # Python + OpenCV/YOLO

# Observabilité / Auth (images publiques par défaut)
IMAGE_PROMETHEUS="prom/prometheus:latest"
IMAGE_GRAFANA="grafana/grafana:latest"
IMAGE_ZIPKIN="openzipkin/zipkin:2.24"
IMAGE_KEYCLOAK="quay.io/keycloak/keycloak:24.0.1"

mkdir -p "${BASE_DIR}"

create_namespace() {
  cat > "${BASE_DIR}/namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
}

create_kafka_strimzi() {
  mkdir -p "${BASE_DIR}/kafka"

  cat > "${BASE_DIR}/kafka/kafka-cluster.yaml" <<EOF
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: sv-kafka
  namespace: ${NAMESPACE}
spec:
  kafka:
    version: 3.7.0
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    storage:
      type: jbod
      volumes:
        - id: 0
          type: persistent-claim
          size: 20Gi
          class: standard
          deleteClaim: false
  zookeeper:
    replicas: 3
    storage:
      type: persistent-claim
      size: 10Gi
      class: standard
      deleteClaim: false
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF
}

create_postgres() {
  mkdir -p "${BASE_DIR}/postgres"

  cat > "${BASE_DIR}/postgres/postgres-statefulset.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: ${NAMESPACE}
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: "smartvision"
            - name: POSTGRES_USER
              value: "smartvision"
            - name: POSTGRES_PASSWORD
              value: "changeme-postgres"
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
EOF
}

create_mongo() {
  mkdir -p "${BASE_DIR}/mongo"

  cat > "${BASE_DIR}/mongo/mongo-statefulset.yaml" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongo
  namespace: ${NAMESPACE}
spec:
  serviceName: mongo
  replicas: 1
  selector:
    matchLabels:
      app: mongo
  template:
    metadata:
      labels:
        app: mongo
    spec:
      containers:
        - name: mongo
          image: mongo:7
          ports:
            - containerPort: 27017
          env:
            - name: MONGO_INITDB_DATABASE
              value: "smartvision"
          volumeMounts:
            - name: data
              mountPath: /data/db
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: 20Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mongo
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: mongo
  ports:
    - port: 27017
      targetPort: 27017
EOF
}

generate_microservice() {
  local name="$1"
  local image="$2"
  local port="$3"

  mkdir -p "${BASE_DIR}/services"

  # Deployment + Service + HPA
  cat > "${BASE_DIR}/services/${name}.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
  labels:
    app: ${name}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${name}
  template:
    metadata:
      labels:
        app: ${name}
    spec:
      containers:
        - name: ${name}
          image: ${image}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: ${port}
          envFrom:
            - configMapRef:
                name: ${name}-config
            - secretRef:
                name: ${name}-secret
---
apiVersion: v1
kind: Service
metadata:
  name: ${name}
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: ${name}
  ports:
    - port: ${port}
      targetPort: ${port}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${name}-hpa
  namespace: ${NAMESPACE}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${name}
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
EOF

  # ConfigMap avec mapping direct sur les propriétés Spring
  cat > "${BASE_DIR}/services/${name}-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${name}-config
  namespace: ${NAMESPACE}
data:
  SPRING_PROFILES_ACTIVE: "prod"

  # Kafka
  SPRING_KAFKA_BOOTSTRAP_SERVERS: "sv-kafka-kafka-bootstrap:9092"

  # Datasource PostgreSQL
  SPRING_DATASOURCE_URL: "jdbc:postgresql://postgres:5432/smartvision"
  SPRING_DATASOURCE_USERNAME: "smartvision"
  SPRING_DATASOURCE_PASSWORD: "changeme-postgres"

  # MongoDB
  SPRING_DATA_MONGODB_URI: "mongodb://mongo:27017/smartvision"

  # Eureka / Config / Observabilité (à adapter selon tes properties)
  EUREKA_CLIENT_SERVICEURL_DEFAULTZONE: "http://eureka-server:8761/eureka/"
  SPRING_CLOUD_CONFIG_URI: "http://config-server:8888"

  MANAGEMENT_ZIPKIN_TRACING_ENDPOINT: "http://zipkin:9411/api/v2/spans"
  MANAGEMENT_TRACING_SAMPLING_PROBABILITY: "1.0"
  MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE: "health,info,prometheus"
EOF

  # Secret placeholder pour futurs secrets sensibles (JWT, etc.)
  cat > "${BASE_DIR}/services/${name}-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${name}-secret
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  JWT_SECRET: "changeme-jwt-secret"
EOF
}

generate_ai_engine() {
  mkdir -p "${BASE_DIR}/ai-engine"

  cat > "${BASE_DIR}/ai-engine/ai-engine.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ai-engine
  namespace: ${NAMESPACE}
  labels:
    app: ai-engine
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ai-engine
  template:
    metadata:
      labels:
        app: ai-engine
    spec:
      containers:
        - name: ai-engine
          image: ${IMAGE_AI_ENGINE}
          imagePullPolicy: IfNotPresent
          env:
            - name: KAFKA_BOOTSTRAP_SERVERS
              value: "sv-kafka-kafka-bootstrap:9092"
            - name: INPUT_TOPIC
              value: "video-frames"
            - name: KAFKA_TOPIC_DETECTIONS
              value: "video-detections"
            - name: RTSP_CAM1
              value: "rtsp://admin:password@192.168.1.100:554/stream1"
            - name: RTSP_CAM2
              value: "rtsp://admin:password@192.168.1.101:554/stream1"
            - name: WEBSOCKET_PORT
              value: "8765"
            - name: PLATE_MODEL_PATH
              value: "/app/models/license_plate.pt"
            - name: FACE_MODEL_PATH
              value: "/app/models/yolov8n-face.pt"
            - name: LOG_LEVEL
              value: "INFO"
            - name: MONGO_URI
              value: "mongodb://mongo:27017/smartvision"
          ports:
            - containerPort: 8765
              name: ws
          volumeMounts:
            - name: models
              mountPath: /app/models
      volumes:
        - name: models
          persistentVolumeClaim:
            claimName: ai-engine-models-pvc
---
apiVersion: v1
kind: Service
metadata:
  name: ai-engine
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: ai-engine
  ports:
    - port: 8765
      targetPort: 8765
      name: ws
EOF
}

create_ingress_api_gateway() {
  mkdir -p "${BASE_DIR}/ingress"

  cat > "${BASE_DIR}/ingress/api-gateway-ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-gateway-ingress
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: smartvision.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-gateway
                port:
                  number: 8080
EOF
}

create_prometheus() {
  mkdir -p "${BASE_DIR}/observability"

  cat > "${BASE_DIR}/observability/prometheus-configmap.yaml" <<EOF
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
      - job_name: 'smartvision-microservices'
        static_configs:
          - targets:
              - 'video-core:8080'
              - 'video-storage:8081'
              - 'video-analyzer:8090'
              - 'api-gateway:8080'
        metrics_path: /actuator/prometheus
EOF

  cat > "${BASE_DIR}/observability/prometheus.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
  labels:
    app: prometheus
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
          image: ${IMAGE_PROMETHEUS}
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
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: prometheus
  ports:
    - port: 9090
      targetPort: 9090
EOF
}

create_grafana() {
  cat > "${BASE_DIR}/observability/grafana.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: grafana-admin
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  admin-user: "admin"
  admin-password: "changeme-grafana"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: ${NAMESPACE}
  labels:
    app: grafana
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
          image: ${IMAGE_GRAFANA}
          env:
            - name: GF_SECURITY_ADMIN_USER
              valueFrom:
                secretKeyRef:
                  name: grafana-admin
                  key: admin-user
            - name: GF_SECURITY_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: grafana-admin
                  key: admin-password
          ports:
            - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: grafana
  ports:
    - port: 3000
      targetPort: 3000
EOF
}

create_zipkin() {
  cat > "${BASE_DIR}/observability/zipkin.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zipkin
  namespace: ${NAMESPACE}
  labels:
    app: zipkin
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
          image: ${IMAGE_ZIPKIN}
          ports:
            - containerPort: 9411
---
apiVersion: v1
kind: Service
metadata:
  name: zipkin
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: zipkin
  ports:
    - port: 9411
      targetPort: 9411
EOF
}

create_keycloak() {
  mkdir -p "${BASE_DIR}/keycloak"

  cat > "${BASE_DIR}/keycloak/keycloak-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-admin-cred
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  KEYCLOAK_ADMIN: "admin"
  KEYCLOAK_ADMIN_PASSWORD: "changeme-keycloak"
EOF

  cat > "${BASE_DIR}/keycloak/keycloak.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
  labels:
    app: keycloak
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
          image: ${IMAGE_KEYCLOAK}
          args: ["start-dev"]
          env:
            - name: KEYCLOAK_ADMIN
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin-cred
                  key: KEYCLOAK_ADMIN
            - name: KEYCLOAK_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin-cred
                  key: KEYCLOAK_ADMIN_PASSWORD
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: ${NAMESPACE}
spec:
  type: ClusterIP
  selector:
    app: keycloak
  ports:
    - port: 8080
      targetPort: 8080
EOF
}

main() {
  echo ">> Génération des manifestes Kubernetes dans ${BASE_DIR}/ pour le namespace ${NAMESPACE}"

  create_namespace
  create_kafka_strimzi
  create_postgres
  create_mongo

  # Microservices Spring Boot
  generate_microservice "video-core"      "${IMAGE_VIDEO_CORE}"      8080
  generate_microservice "video-storage"   "${IMAGE_VIDEO_STORAGE}"   8081
  generate_microservice "video-analyzer"  "${IMAGE_VIDEO_ANALYZER}"  8090
  generate_microservice "config-server"   "${IMAGE_CONFIG_SERVER}"   8888
  generate_microservice "eureka-server"   "${IMAGE_EUREKA_SERVER}"   8761
  generate_microservice "api-gateway"     "${IMAGE_API_GATEWAY}"     8080

  # IA Python
  generate_ai_engine

  # Ingress
  create_ingress_api_gateway

  # Observabilité + Auth
  create_prometheus
  create_grafana
  create_zipkin
  create_keycloak

  echo ">> Terminé."
  echo "   Appliquer les manifestes avec :"
  echo "   kubectl apply -f ${BASE_DIR}/namespace.yaml"
  echo "   kubectl apply -f ${BASE_DIR}/kafka/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/postgres/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/mongo/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/services/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/ai-engine/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/observability/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/keycloak/ -n ${NAMESPACE}"
  echo "   kubectl apply -f ${BASE_DIR}/ingress/ -n ${NAMESPACE}"
}

main "$@"

