variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Lowercase prefix used for bucket, function and role names"
  type        = string
  default     = "jpeg-to-pdf"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers and hyphens."
  }
}

variable "lambda_memory_mb" {
  type    = number
  default = 256
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 60
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "force_destroy_buckets" {
  description = "Allow terraform destroy to delete non-empty buckets"
  type        = bool
  default     = false
}