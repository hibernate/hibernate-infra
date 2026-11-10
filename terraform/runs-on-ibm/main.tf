terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "hibernate-terraform-state-ibm"
    key            = "runs-on/terraform.tfstate"
    region         = "us-east-1"
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
      Project = "runs-on-ibm-hibernate"
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

  name = "runs-on-ibm-hibernate"
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

# See https://pages.github.ibm.com/CISO-Platform-Network-Defense/Uptycs-Documentation/Onboarding/Tagging/
data "aws_secretsmanager_secret_version" "uptycs_tags" {
  secret_id = var.uptycs_tags_secret_name
}

# --- Shared Artifacts ---

resource "aws_s3_bucket" "shared_artifacts" {
  bucket = "runs-on-ibm-hibernate-shared"
}

resource "aws_s3_bucket_public_access_block" "shared_artifacts" {
  bucket = aws_s3_bucket.shared_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "shared_deb" {
  for_each = fileset("${path.module}/shared", "*.deb")

  bucket = aws_s3_bucket.shared_artifacts.id
  key    = each.value
  source = "${path.module}/shared/${each.value}"
  etag   = filemd5("${path.module}/shared/${each.value}")
}

data "aws_iam_policy_document" "runner_s3_read" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.shared_artifacts.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.shared_artifacts.arn}/*"]
  }
}

resource "aws_iam_policy" "runner_s3_read" {
  name_prefix = "runs-on-ibm-hibernate-runner-s3-"
  policy      = data.aws_iam_policy_document.runner_s3_read.json
}

# --- RunsOn Fleet ---

resource "github_actions_runner_group" "runs_on" {
  name                       = "runs-on-ibm-hibernate"
  visibility                 = "all"
  allows_public_repositories = true
}

module "runs_on_fleet" {
  source  = "runs-on/runs-on/aws//modules/fleet"
  version = "v3.5.0"

  stack_name  = "runs-on-ibm-hibernate"
  license_key = data.aws_secretsmanager_secret_version.license_key.secret_string
  environment = "ibm"
  email       = var.alert_email

  github_app_id          = var.github_app_id
  github_app_private_key = data.aws_secretsmanager_secret_version.github_app_private_key.secret_string

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnets

  runner_custom_policy_arns = [aws_iam_policy.runner_s3_read.arn]

  runners = {
    standard-x64 = {
      # See "Choosing instance families" in the top-level README
      cpu        = [4, 8]
      ram        = 16
      family     = ["m5a", "m6a", "m8i", "r8a", "c5a", "c6a", "c7a"]
      spot       = "capacity-optimized"
      image      = "ubuntu24-full-x64"
      volume     = "80gb"
      # See https://pages.github.ibm.com/CISO-Platform-Network-Defense/Uptycs-Documentation/Onboarding/Getting_started/ for details
      preinstall = "aws s3 cp s3://${aws_s3_bucket.shared_artifacts.id}/ /tmp/shared/ --recursive --exclude '*' --include '*.deb' && dpkg -i /tmp/shared/*.deb && sudo /usr/bin/osqueryd --osquery_tags \"UT/REDHAT,CCODE/REDHAT,UPDATES/PROD,AV/YES,${data.aws_secretsmanager_secret_version.uptycs_tags.secret_string}\" && sudo systemctl start osqueryd"
    }
  }

  fleets = {
    linux-standard = {
      runner       = "standard-x64"
      runner_group = github_actions_runner_group.runs_on.name
    }
  }
}
