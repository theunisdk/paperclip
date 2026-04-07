variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type — t3.xlarge (4 vCPU/16GB) for up to 4 agents, t3.2xlarge (8/32GB) for up to 8"
  default     = "t3.xlarge"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  default     = 50
}

variable "ssh_key_name" {
  description = "Name of an existing AWS key pair for SSH access (fallback if Tailscale is unavailable)"
  default     = null
}

variable "allowed_cidr" {
  description = "CIDR block for SSH fallback access. Not needed if using Tailscale exclusively."
  default     = null
}

variable "anthropic_api_key" {
  description = "Anthropic API key — used by OpenClaw agent instances"
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key for joining the tailnet. Generate at https://login.tailscale.com/admin/settings/keys"
  sensitive   = true
}

variable "tailscale_hostname" {
  description = "Hostname the instance will use on the tailnet"
  default     = "paperclip"
}

variable "paperclip_gateway_token" {
  description = "Shared token for OpenClaw gateway auth. Auto-generated if left empty."
  sensitive   = true
  default     = ""
}

variable "openclaw_agent_count" {
  description = "Number of OpenClaw agent slots to pre-provision (ports 18800+)"
  default     = 4
}

variable "project_name" {
  description = "Name prefix for all AWS resources"
  default     = "paperclip"
}
