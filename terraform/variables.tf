variable "db_host" {
  description = "Database hostname"
  type        = string
  default = "postgres-service.default.svc.cluster.local"
}

variable "db_admin" {
  description = "Database admin username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}

variable "db_replicas" {
    description = "How many replicas of the database"
    type = number
    default = 1
}

variable "app_replicas" {
    description = "How many replicas of the web app"
    type = number
    default = 1
}

variable "project_name" {
    description = "How many replicas of the web app"
    type = string
    default = "maks-453602"
}