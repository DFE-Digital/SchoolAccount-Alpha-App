variable "ghcr_username" {
  description = "GitHub actor for GHCR auth"
  type        = string
}

variable "ghcr_token" {
  description = "GitHub token for GHCR auth"
  type        = string
  sensitive   = true
}