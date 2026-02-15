variable "node_count" {
  description = "Nombre de noeuds dans le cluster Swarm (1 manager + N-1 workers)"
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= 2
    error_message = "Au moins 2 noeuds sont nécessaires (1 manager + 1 worker)."
  }
}

variable "vm_memory" {
  description = "Mémoire RAM par VM (Mo)"
  type        = number
  default     = 2048
}

variable "vm_cpus" {
  description = "Nombre de vCPUs par VM"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Taille du disque par VM (octets) — 20 Go par défaut"
  type        = number
  default     = 21474836480
}

variable "base_image_url" {
  description = "URL ou chemin local de l'image cloud Ubuntu 22.04 (qcow2)"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
}
