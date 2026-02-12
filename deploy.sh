#!/bin/bash
set -e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== 🚀 DÉPLOIEMENT AUTOMATISÉ GLPI SWARM ===${NC}"


# Ensure vboxnet0 exists
if ! VBoxManage list hostonlyifs | grep -q "vboxnet0"; then
    echo "Creating vboxnet0 network..."
    VBoxManage hostonlyif create
fi

# Ensure DHCP is on for vboxnet0 (Essential for VMs to get IP)
echo "Configuring DHCP for vboxnet0..."
VBoxManage dhcpserver add --ifname vboxnet0 --ip 192.168.56.2 --netmask 255.255.255.0 --lowerip 192.168.56.100 --upperip 192.168.56.200 --enable 2>/dev/null || VBoxManage dhcpserver modify --ifname vboxnet0 --enable 2>/dev/null || true

# Force cleanup of old VMs...
for i in {1..3}; do
  VM="glpi-node-$(printf "%02d" $i)"
  if VBoxManage list vms | grep -q "\"$VM\""; then
    echo "Deleting existing VM: $VM"
    VBoxManage controlvm "$VM" poweroff 2>/dev/null || true
    sleep 2
    VBoxManage unregistervm "$VM" --delete 2>/dev/null || true
  fi
done

cd infra
echo "Cleaning Terraform state..."
rm -rf .terraform terraform.tfstate* .terraform.lock.hcl
terraform init
terraform apply -auto-approve -parallelism=1
cd ..

# 2. Attente SSH
echo -e "${BLUE}[2/4] Attente de la connectivité SSH...${NC}"

# Extract IPs from inventory
IPS=$(grep "ansible_host" config/inventory.ini | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')

if [ -z "$IPS" ]; then
  echo -e "${RED}Erreur : Aucune IP trouvée dans l'inventaire.${NC}"
  exit 1
fi

for IP in $IPS; do
  echo "Attente SSH sur $IP..."
  count=0
  while ! nc -z -w 5 $IP 22; do
    echo "  En attente de $IP:22... (${count}s)"
    sleep 5
    count=$((count+5))
    if [ $count -ge 300 ]; then
        echo -e "${RED}Timeout: Impossible de joindre $IP sur le port 22.${NC}"
        exit 1
    fi
  done
  echo "  $IP est accessible !"
done

# Petit délai supplémentaire pour être sûr que le service est stable
sleep 10

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

if [ -z "$MANAGER_IP" ]; then
    echo -e "${RED}Erreur: Impossible de récupérer l'IP du manager. Vérifiez infra/terraform.tfstate ou config/inventory.ini.${NC}"
    exit 1
fi

echo "Transfert des fichiers vers le Manager ($MANAGER_IP)..."
scp -o StrictHostKeyChecking=no -r app/* vagrant@$MANAGER_IP:/home/vagrant/

echo "Lancement du script d'init sur le Manager..."
ssh -o StrictHostKeyChecking=no vagrant@$MANAGER_IP "chmod +x /home/vagrant/scripts/*.sh && /home/vagrant/scripts/init-stack.sh"

echo "Attente du déploiement de la stack (60s)..."
sleep 60

echo "Lancement de la configuration SSL Automatisee..."
ssh -o StrictHostKeyChecking=no vagrant@$MANAGER_IP "/home/vagrant/scripts/init-letsencrypt.sh"

echo -e "${GREEN}=== ✅ SUCCÈS ! DÉPLOIEMENT TERMINÉ ===${NC}"
echo -e "${BLUE}Pour accéder à GLPI en HTTPS avec le domaine 'glpi.local' :${NC}"
echo -e "1. Ajoutez cette ligne à votre fichier /etc/hosts (sur votre machine hôte) :"
echo -e "${GREEN}$MANAGER_IP glpi.local${NC}"
echo -e "2. Ouvrez votre navigateur sur : ${GREEN}https://glpi.local${NC}"
echo -e "(Si vous utilisez un certificat auto-signé, acceptez l'avertissement de sécurité)"