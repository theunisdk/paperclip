terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate gateway token if not provided
resource "random_id" "gateway_token" {
  byte_length = 24
}

locals {
  gateway_token = var.paperclip_gateway_token != "" ? var.paperclip_gateway_token : random_id.gateway_token.hex
  has_ssh       = var.ssh_key_name != null && var.allowed_cidr != null
}

# --- Data Sources ---

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Networking ---

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group ---

resource "aws_security_group" "main" {
  name_prefix = "${var.project_name}-"
  description = "Paperclip server - Tailscale handles access, SG is minimal"
  vpc_id      = aws_vpc.main.id

  # SSH fallback — only if key pair and CIDR are provided
  dynamic "ingress" {
    for_each = local.has_ssh ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_cidr]
      description = "SSH fallback"
    }
  }

  # All outbound (Anthropic API, npm, Tailscale coordination)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = { Name = "${var.project_name}-sg" }

  lifecycle { create_before_destroy = true }
}

# --- EC2 Instance ---

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.main.id]

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    anthropic_api_key       = var.anthropic_api_key
    paperclip_gateway_token = local.gateway_token
    openclaw_agent_count    = var.openclaw_agent_count
    tailscale_auth_key      = var.tailscale_auth_key
    tailscale_hostname      = var.tailscale_hostname
    ceo_claude_md           = file("${path.module}/templates/ceo-claude.md")
    spawn_skill_md          = file("${path.module}/templates/spawn-openclaw-agent-skill.md")
  })


  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "${var.project_name}-server" }
}

# --- Elastic IP (for stable outbound + SSH fallback) ---

resource "aws_eip" "main" {
  instance = aws_instance.main.id
  domain   = "vpc"

  tags = { Name = "${var.project_name}-eip" }
}
