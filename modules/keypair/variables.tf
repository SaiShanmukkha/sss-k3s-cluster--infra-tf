variable "cluster_name"{
    type = string
    description = "Name prefix for resources"
    nullable = false
    sensitive = false
    ephemeral = false
}

variable "tags" {
  type = map(string)
  description = "Common Tags Across all Resources"
  default = {}
}

variable "save_keys_locally" {
  description = "Save private keys as local .pem files under keys/ (gitignored). Set false in CI/CD."
  type        = bool
  default     = true
}