# GLPI High Availability - Docker Swarm

Déploiement automatisé d'une infrastructure GLPI haute disponibilité sur un cluster Docker Swarm de 3 nœuds, provisionné par Terraform/Vagrant et configuré par Ansible.

## Architecture

- **3 VMs Ubuntu 22.04** (VirtualBox via Vagrant) : 1 Manager + 2 Workers
- **3 Nginx** (mode global) : Reverse proxy + load balancing + SSL
- **1 GLPI** : Application web de gestion de parc informatique
- **1 MariaDB** : Base de données isolée sur réseau interne
- **NFS** : Partage de fichiers entre les nœuds (configs Nginx, certificats, données GLPI)
- **Certbot** : Gestion automatique des certificats SSL (Let's Encrypt ou auto-signé)

## Pré-requis

| Outil        | Version min. |
|--------------|-------------|
| Terraform    | >= 0.13     |
| Vagrant      | >= 2.3      |
| Ansible      | >= 2.9      |
| VirtualBox   | >= 6.0      |
| sshpass      | —           |

## Lancement

```bash
chmod +x deploy.sh
./deploy.sh
```

Le script gère tout automatiquement :
1. Vérification des pré-requis
2. Génération de la clé SSH Ed25519
3. Provisionnement des 3 VMs (Terraform + Vagrant)
4. Déploiement des clés SSH + inventaire Ansible
5. Configuration système & cluster (Ansible : Docker, NFS, UFW, Swarm)
6. Déploiement de la stack Docker (Nginx, GLPI, MariaDB, Certbot) + SSL

## Après le déploiement

1. Accéder à GLPI via `http://<MANAGER_IP>` ou `https://<MANAGER_IP>` (par défaut : `192.168.56.101`)
2. Suivre le wizard d'installation GLPI
3. Utiliser les credentials MariaDB affichés en fin de déploiement (host: `mariadb`, port: `3306`, db: `glpi`, user: `glpi`)

## Destruction de l'infrastructure

```bash
cd infra && terraform destroy -auto-approve
```

## Documentation complète

Voir [DOCUMENTATION.md](DOCUMENTATION.md) pour les détails sur l'architecture, la sécurité et la performance.

## Auteurs

VERGUET Romain / DA SILVA Alexy / ZIJP Quentin - ESGI AL
