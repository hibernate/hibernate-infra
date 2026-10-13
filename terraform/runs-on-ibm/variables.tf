variable "aws_region" {
  type = string
}

variable "github_org" {
  type = string
}

variable "github_app_id" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "license_key_secret_name" {
  type    = string
  default = "runs-on/license-key"
}

variable "github_app_private_key_secret_name" {
  type    = string
  default = "runs-on/github-app-private-key"
}
