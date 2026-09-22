terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "lms"
  cidr = "10.42.0.0/24"

  azs            = ["us-west-2a"]
  public_subnets = ["10.42.0.0/26"]

  map_public_ip_on_launch = true
  enable_nat_gateway      = false
}

data "aws_ssm_parameter" "debian_13_arm64_ami" {
  name = "/aws/service/debian/release/13/latest/arm64"
}

variable "admin_cidr" {
  description = "Public IPv4 CIDR allowed to connect over SSH, for example 203.0.113.10/32"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key imported into AWS"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

resource "aws_key_pair" "lms" {
  key_name   = "lms"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

module "lms_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 6.0"

  name        = "lms"
  description = "Network access for the LMS instance"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    ssh = {
      description = "SSH from administrator"
      from_port   = 22
      to_port     = 22
      ip_protocol = "tcp"
      cidr_ipv4   = var.admin_cidr
    }
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  egress_rules = {
    internet = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = {
    Name = "lms"
  }
}

resource "aws_instance" "lms-instance" {
  ami                         = data.aws_ssm_parameter.debian_13_arm64_ami.value
  instance_type               = "t4g.medium"
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids      = [module.lms_security_group.id]
  key_name                    = aws_key_pair.lms.key_name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
  }

  tags = {
    Name = "lms"
  }
}

resource "aws_eip" "lms" {
  domain   = "vpc"
  instance = aws_instance.lms-instance.id

  tags = {
    Name = "lms"
  }
}

output "lms_public_ip" {
  description = "Static public IPv4 address of the LMS instance"
  value       = aws_eip.lms.public_ip
}
