#!/bin/bash
set -e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== 🚀 DÉPLOIEMENT AUTOMATISÉ GLPI SWARM ===${NC}"

# 1. Terraform
echo -e "${BLUE}[1/4] Provisioning Infrastructure (Terraform)...${NC}"
cd infra
terraform init
terraform apply -auto-approve
cd ..

# 2. Attente SSH
echo -e "${BLUE}[2/4] Attente de la connectivité SSH...${NC}"
sleep 30 # Temps de boot des VMs

# 3. Ansible
echo -e "${BLUE}[3/4] Configuration Système & Cluster (Ansible)...${NC}"
cd config
# On exporte une variable pour ignorer la vérification des clés SSH (contexte local)
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i inventory.ini playbook.yml
cd ..

# 4. Déploiement App
echo -e "${BLUE}[4/4] Déploiement de la Stack GLPI...${NC}"
# On récupère l'IP du manager depuis l'inventaire généré
MANAGER_IP=$(grep "manager" config/inventory.ini | head -1 | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')

echo "Transfert des fichiers vers le Manager ($MANAGER_IP)..."
scp -o StrictHostKeyChecking=no -r app/* vagrant@$MANAGER_IP:/home/vagrant/

echo "Lancement du script d'init sur le Manager..."
ssh -o StrictHostKeyChecking=no vagrant@$MANAGER_IP "chmod +x /home/vagrant/scripts/init-stack.sh && /home/vagrant/scripts/init-stack.sh"

echo -e "${GREEN}=== ✅ SUCCÈS ! GLPI EST ACCESSIBLE SUR : http://$MANAGER_IP ===${NC}"