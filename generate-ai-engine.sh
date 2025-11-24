#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# SmartVision - Générateur du programme IA "ai_engine"
# ----------------------------------------------------------------------------
# Usage :
#   chmod +x generate-ai-engine.sh
#   ./generate-ai-engine.sh               # génère ./ai-engine/{ai_engine.py,requirements.txt,Dockerfile}
#   ./generate-ai-engine.sh /chemin/dir   # génère /chemin/dir/...
# ============================================================================

OUTPUT_DIR="${1:-ai-engine}"
PY_FILE="$OUTPUT_DIR/ai_engine.py"
REQ_FILE="$OUTPUT_DIR/requirements.txt"
DOCKERFILE="$OUTPUT_DIR/Dockerfile"

echo "📂 Dossier cible : $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "📝 Génération de ai_engine.py ..."
cat > "$PY_FILE" << 'PY'
import cv2
import asyncio
import json
import websockets
from kafka import KafkaProducer
from ultralytics import YOLO
import numpy as np
import logging
from datetime import datetime
import os

# Configuration (surchargée par variables d'environnement si besoin)
RTSP_URLS = {
    "cam1": os.getenv("RTSP_CAM1", "rtsp://admin:password@192.168.1.100:554/stream1"),
    "cam2": os.getenv("RTSP_CAM2", "rtsp://admin:password@192.168.1.101:554/stream1"),
}

KAFKA_BROKERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092").split(",")
WEBSOCKET_PORT = int(os.getenv("WEBSOCKET_PORT", "8765"))

# Initialisation Kafka
producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKERS,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

# Modèles IA
plate_detector = YOLO(os.getenv("PLATE_MODEL_PATH", "models/license_plate.pt"))
face_detector = YOLO(os.getenv("FACE_MODEL_PATH", "models/yolov8n-face.pt"))
tracker = {}  # Pour le suivi multi-caméra (placeholder)


async def process_rtsp_stream(camera_id, rtsp_url):
    """Capture et traite un flux RTSP en temps réel"""
    cap = cv2.VideoCapture(rtsp_url)

    if not cap.isOpened():
        logging.error(f"Impossible d'ouvrir le flux RTSP: {rtsp_url}")
        return

    logging.info(f"Démarrage du traitement pour la caméra: {camera_id}")

    while True:
        ret, frame = cap.read()
        if not ret:
            logging.warning(f"Frame perdue sur {camera_id}")
            await asyncio.sleep(1)
            continue

        # Traitement IA
        results = await process_frame(camera_id, frame)

        # Publication des résultats
        await publish_results(camera_id, results)

        # Pour ne pas surcharger le CPU
        await asyncio.sleep(0.03)  # ~30 FPS

    cap.release()


async def process_frame(camera_id, frame):
    """Traitement IA sur une frame"""
    results = {
        "camera_id": camera_id,
        "timestamp": datetime.now().isoformat(),
        "detections": []
    }

    # Détection des plaques d'immatriculation
    plates = plate_detector(frame, conf=0.7)
    for plate in plates:
        for box in plate.boxes:
            plate_data = extract_plate_data(box, frame)
            results["detections"].append({
                "type": "license_plate",
                "data": plate_data,
                "tracking_id": track_object(camera_id, plate_data["bbox"])
            })

    # Reconnaissance faciale
    faces = face_detector(frame, conf=0.6)
    for face in faces:
        for box in face.boxes:
            face_data = extract_face_data(box, frame)
            results["detections"].append({
                "type": "face",
                "data": face_data,
                "tracking_id": track_object(camera_id, face_data["bbox"])
            })

    return results


def extract_plate_data(box, frame):
    """Extrait les données de plaque d'immatriculation"""
    bbox = box.xyxy[0].tolist()
    confidence = float(box.conf[0])

    # OCR pour lire la plaque (exemple avec EasyOCR ou Tesseract)
    x1, y1, x2, y2 = map(int, bbox)
    plate_image = frame[y1:y2, x1:x2]

    # Ici vous intégreriez votre OCR (EasyOCR, Tesseract, etc.)
    plate_text = "AB-123-CD"  # Remplacer par OCR réel

    return {
        "bbox": bbox,
        "confidence": confidence,
        "text": plate_text,
        "timestamp": datetime.now().isoformat()
    }


def extract_face_data(box, frame):
    """Extrait les données faciales"""
    bbox = box.xyxy[0].tolist()
    confidence = float(box.conf[0])

    # Ici vous pourriez ajouter de la reconnaissance faciale
    # avec FaceNet, DeepFace, etc.
    face_embedding = []  # Placeholder pour un vecteur d'embedding

    return {
        "bbox": bbox,
        "confidence": confidence,
        "embedding": face_embedding,
        "timestamp": datetime.now().isoformat()
    }


def track_object(camera_id, bbox):
    """Suivi d'objets entre les frames"""
    # Implémentation simple - utiliser DeepSORT ou SORT pour la production
    return f"{camera_id}_track_{hash(tuple(bbox)) % 1000}"


async def publish_results(camera_id, results):
    """Publie les résultats sur Kafka et WebSocket"""
    # Kafka pour le backend Java
    producer.send(os.getenv("KAFKA_TOPIC_DETECTIONS", "video-detections"), value=results)

    # WebSocket pour le live streaming
    await broadcast_websocket(results)


connected_websockets = set()


async def broadcast_websocket(data):
    """Diffuse les résultats via WebSocket à tous les clients connectés"""
    if not connected_websockets:
        return
    message = json.dumps(data)
    await asyncio.gather(*[ws.send(message) for ws in connected_websockets])


async def websocket_handler(websocket, path):
    """Serveur WebSocket pour le live stream"""
    logging.info(f"Client WebSocket connecté depuis {websocket.remote_address}")
    connected_websockets.add(websocket)
    try:
        async for _ in websocket:
            # Ici on pourrait traiter des commandes venant du client
            pass
    except Exception as e:
        logging.warning(f"Erreur WebSocket: {e}")
    finally:
        connected_websockets.remove(websocket)
        logging.info(f"Client WebSocket déconnecté {websocket.remote_address}")


async def main():
    """Point d'entrée principal"""
    # Démarrer les traitements RTSP
    processing_tasks = [
        process_rtsp_stream(cam_id, url)
        for cam_id, url in RTSP_URLS.items()
    ]

    # Démarrer le serveur WebSocket
    ws_server = websockets.serve(websocket_handler, "0.0.0.0", WEBSOCKET_PORT)
    logging.info(f"Serveur WebSocket démarré sur le port {WEBSOCKET_PORT}")

    await asyncio.gather(ws_server, *processing_tasks)


if __name__ == "__main__":
    logging.basicConfig(
        level=os.getenv("LOG_LEVEL", "INFO"),
        format="%(asctime)s [%(levelname)s] %(name)s - %(message)s"
    )
    asyncio.run(main())
PY

echo "🧾 Génération de requirements.txt ..."
cat > "$REQ_FILE" << 'REQ'
# Dépendances IA SmartVision - ai_engine
opencv-python-headless
numpy
kafka-python
websockets
ultralytics
torch
torchvision
REQ

echo "🐳 Génération du Dockerfile ..."
cat > "$DOCKERFILE" << 'DOCKER'
# Image de base Python slim pour réduire la taille
FROM python:3.11-slim

# Variables d'environnement de base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Dépendances système pour OpenCV, RTSP, etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fichiers de requirements
COPY requirements.txt /app/requirements.txt

# Installation des dépendances Python
RUN pip install --no-cache-dir -r /app/requirements.txt

# Copie du code
COPY ai_engine.py /app/ai_engine.py

# Dossier pour les modèles (montable en volume)
RUN mkdir -p /app/models
VOLUME ["/app/models"]

# Port WebSocket (doit matcher WEBSOCKET_PORT)
EXPOSE 8765

# Commande de lancement
CMD ["python", "/app/ai_engine.py"]
DOCKER

echo "✅ Fichiers générés :"
echo "   - $PY_FILE"
echo "   - $REQ_FILE"
echo "   - $DOCKERFILE"

