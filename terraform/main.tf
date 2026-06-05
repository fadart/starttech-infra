terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "starttech-terraform-state-035"
    key    = "starttech/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
}

module "storage" {
  source = "./modules/storage"

  project_name = var.project_name
  environment  = var.environment
}

module "compute" {
  source = "./modules/compute"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.networking.vpc_id
  public_subnet_ids         = module.networking.public_subnet_ids
  private_subnet_ids        = module.networking.private_subnet_ids
  alb_security_group_id     = module.networking.alb_security_group_id
  backend_security_group_id = module.networking.backend_security_group_id
  redis_security_group_id   = module.networking.redis_security_group_id
  ami_id                    = var.ami_id
  instance_type             = var.instance_type
  key_name                  = var.key_name
  frontend_bucket           = module.storage.frontend_bucket_name
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
}
