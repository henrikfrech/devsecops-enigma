variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "project-b4952354-c0d7-4e0a-a90"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Primary GCP zone"
  type        = string
  default     = "europe-west1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "wiz-gke"
}

variable "network_name" {
  default = "wiz-vpc"
}

variable "subnet_name" {
  default = "wiz-subnet"
}

variable "subnet_cidr" {
  default = "10.0.0.0/16"
}

variable "pods_cidr" {
  default = "10.10.0.0/16"
}

variable "services_cidr" {
  default = "10.20.0.0/20"
}

variable "mongo_vm_name" {
  description = "MongoDB VM name"
  type        = string
  default     = "mongo-vm"
}

variable "mongo_machine_type" {
  description = "MongoDB VM machine type"
  type        = string
  default     = "e2-medium"
}

variable "mongo_username" {
  description = "MongoDB application username"
  type        = string
  default     = "appuser"
}

variable "mongo_password" {
  description = "MongoDB application password"
  type        = string
  sensitive   = true
  default     = "Password123!#"
}

variable "mongo_db_name" {
  description = "MongoDB database name"
  type        = string
  default     = "wizlab"
}

variable "retention_days" {
  type    = number
  default = 7
}
