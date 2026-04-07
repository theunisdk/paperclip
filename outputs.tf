output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.main.id
}

output "public_ip" {
  description = "Public IP (for SSH fallback — prefer Tailscale)"
  value       = aws_eip.main.public_ip
}

output "tailscale_url" {
  description = "Paperclip UI via Tailscale"
  value       = "http://${var.tailscale_hostname}:3100"
}

output "tailscale_ssh" {
  description = "SSH via Tailscale"
  value       = "ssh ubuntu@${var.tailscale_hostname}"
}

output "setup_log_command" {
  description = "Check cloud-init progress"
  value       = "ssh ubuntu@${var.tailscale_hostname} tail -f /var/log/paperclip-setup.log"
}
