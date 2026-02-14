variable "node_count" {
  description = "Nombre de noeuds dans le cluster Swarm (1 manager + N-1 workers)"
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= 2
    error_message = "Au moins 2 noeuds sont nécessaires (1 manager + 1 worker)."
  }
}
