# GLPI High Availability Swarm

Ce projet déploie une infrastructure complète GLPI sur 3 nœuds Docker Swarm via Terraform et Ansible.

## Pré-requis

1. Terraform installé.
2. Ansible installé.
3. VirtualBox installé (avec un réseau Host-Only nommé `vboxnet1` configuré dans Fichier > Gestionnaire de réseau hôte).

## Lancement Rapide

Exécutez simplement le script maître :

```bash
./deploy.sh
```

## Architecture

- **Infrastructure** : 3 VMs Ubuntu (1 Manager, 2 Workers).
- **Stockage** : Serveur NFS sur le Manager, monté sur tous les Workers (nécessaire pour la persistance des données dans le Swarm).
- **Frontend** : 3 instances Nginx (Mode Global) avec Load Balancing.
- **Backend** : MariaDB isolée dans un réseau overlay interne.
- **Sécurité** : Utilisation de Docker Secrets pour les mots de passe BDD.

## Auteurs

VERGUET Romain / DA SILVA Alexy / ZIJP Quentin - ESGI AL
