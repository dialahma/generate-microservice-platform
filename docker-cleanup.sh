#!/bin/bash
# 🔥 Supprimer les conteneurs arrêtés et anciens
docker rm -f $(docker ps -a -q --filter "name=video-smartvision-platform") 2>/dev/null

# 🧹 Supprimer les images anciennes du projet
docker rmi -f $(docker images | grep 'video-smartvision-platform' | awk '{print $3}') 2>/dev/null

# 🧽 Nettoyage volumes anonymes
docker volume prune -f

# 🚀 Rebuild propre
cd /app/workspace/java/video/video-smartvision-platform
./deploy-all.sh

