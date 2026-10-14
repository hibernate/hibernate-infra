terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "hibernate-terraform-state-commonhaus"
    key            = "runs-on/terraform.tfstate"
    region         = "us-east-2"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project = "runs-on-hibernate"
    }
  }
}

provider "github" {
  owner = var.github_org
}

# --- VPC ---

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "runs-on-commonhaus"
  cidr = "10.0.0.0/16"

  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnets = ["10.0.0.0/20", "10.0.16.0/20"]

  enable_dns_hostnames = true
  enable_dns_support   = true
}

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.public_route_table_ids
    }
  }
}

# --- Secrets ---

data "aws_secretsmanager_secret_version" "github_app_private_key" {
  secret_id = var.github_app_private_key_secret_name
}

data "aws_secretsmanager_secret_version" "license_key" {
  secret_id = var.license_key_secret_name
}

# --- RunsOn Fleet ---

resource "github_actions_runner_group" "runs_on" {
  name                       = "runs-on-commonhaus"
  visibility                 = "all"
  allows_public_repositories = true
}

module "runs_on_fleet" {
  source  = "runs-on/runs-on/aws//modules/fleet"
  version = "v3.4.0"

  stack_name  = "runs-on-commonhaus"
  license_key = data.aws_secretsmanager_secret_version.license_key.secret_string
  environment = "production"
  email       = var.alert_email

  github_app_id          = var.github_app_id
  github_app_private_key = data.aws_secretsmanager_secret_version.github_app_private_key.secret_string

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnets

  runners = {
    standard-x64 = {
      cpu    = 2
      ram    = 7
      family = ["m7a", "m7i", "m6a", "m6i"]
      image  = "ubuntu24-full-x64"
    }
  }

  fleets = {
    commonhaus-linux-standard = {
      runner       = "standard-x64"
      runner_group = github_actions_runner_group.runs_on.name
    }
  }
}
