#!/bin/bash
# Script exécuté sur le Manager VM

# 1. Création des secrets
echo "Creation des secrets..."
printf "rootpassword123" | docker secret create db_root_password - || true
printf "glpipassword123" | docker secret create db_password - || true

# 2. Création des dossiers partagés via NFS (monté sur /mnt/shared)
mkdir -p /mnt/shared/glpi_data
mkdir -p /mnt/shared/mysql_data
mkdir -p /mnt/shared/certbot_conf
mkdir -p /mnt/shared/certbot_www

# 3. Déploiement de la stack
echo "Deploiement de la stack..."
cd /home/vagrant
docker stack deploy -c docker-stack.yml glpi_stack