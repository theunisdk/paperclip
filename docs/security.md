# Security Overview

This document describes the security measures applied to the Paperclip + OpenClaw EC2 deployment. The goal is zero public attack surface while keeping the setup simple to operate.

## Network Access Model

```
  Internet                    Your Tailnet
  ─────────                   ────────────
      │                            │
      │  ┌──────────────────┐      │
      │  │  AWS VPC         │      │
      │  │                  │      │
      │  │  ┌────────────┐  │      │
      │  │  │ EC2        │  │      │
      ╳  │  │            │◄─┼──────┘  Tailscale (WireGuard)
 no inbound │            │  │
      │  │  │            ├──┼──►  Anthropic API (outbound only)
      │  │  └────────────┘  │
      │  │                  │
      │  └──────────────────┘
      │
```

**No ports are open to the public internet.** The AWS security group allows outbound traffic only. All access to the instance — SSH, Paperclip UI, OpenClaw agent UIs — goes through Tailscale's encrypted WireGuard mesh.

### What Tailscale provides

- **End-to-end encryption** via WireGuard between your devices and the EC2 instance.
- **Identity-based access** — no SSH keys, passwords, or IP allowlists to manage. Your Tailscale identity is your credential.
- **Tailscale SSH** — SSH access authenticated by your tailnet identity, not key files.
- **ACL control** — restrict which tailnet users or devices can reach the instance using [Tailscale ACLs](https://tailscale.com/kb/1018/acls).
- **MagicDNS** — access the instance by hostname (e.g. `paperclip`) instead of IP.

### SSH fallback

An optional SSH fallback is available by providing `ssh_key_name` and `allowed_cidr` in your Terraform variables. This opens port 22 to a single CIDR block as a last resort if Tailscale is unavailable. It is not required and not recommended for normal use.

## OS Hardening

The following hardening is applied automatically during cloud-init (step 2 of the bootstrap):

### SSH Configuration

| Setting | Value | Why |
|---------|-------|-----|
| `PermitRootLogin` | `no` | Prevents direct root access |
| `PasswordAuthentication` | `no` | Keys or Tailscale SSH only |
| `X11Forwarding` | `no` | No GUI forwarding needed |
| `MaxAuthTries` | `3` | Limits brute force window per connection |

### UFW Firewall

The host-level firewall (`ufw`) is configured as:

- **Default deny incoming** — all inbound traffic is dropped unless explicitly allowed.
- **Allow on `tailscale0`** — all traffic from your Tailscale network is permitted.
- **Allow TCP 22** — SSH fallback (only reachable if the security group also allows it).
- **Default allow outgoing** — the instance can reach the internet (Anthropic API, npm, etc.).

This is a second layer on top of the AWS security group. Even if the security group were misconfigured, UFW would still block unexpected inbound traffic.

### fail2ban

Monitors `/var/log/auth.log` for failed SSH login attempts:

- **Max retries:** 3
- **Ban duration:** 1 hour
- **Detection window:** 10 minutes

After 3 failed attempts from an IP within 10 minutes, that IP is banned for 1 hour via iptables.

### Kernel Hardening (sysctl)

| Setting | Value | Purpose |
|---------|-------|---------|
| `net.ipv4.ip_forward` | `1` | Required for Tailscale |
| `net.ipv4.conf.all.accept_redirects` | `0` | Ignore ICMP redirects (prevents route manipulation) |
| `net.ipv4.conf.all.send_redirects` | `0` | Don't send ICMP redirects |
| `net.ipv4.tcp_syncookies` | `1` | SYN flood protection |
| `net.ipv4.conf.all.log_martians` | `1` | Log packets with impossible source addresses |
| `net.ipv4.icmp_echo_ignore_broadcasts` | `1` | Ignore broadcast pings (smurf attack mitigation) |
| `net.ipv4.conf.all.accept_source_route` | `0` | Disable source routing (prevents routing attacks) |

### Automatic Security Updates

`unattended-upgrades` is configured to:

- Check for updates daily.
- Install security patches automatically.
- Clean old packages weekly.

This ensures the instance stays patched without manual intervention.

## AWS Infrastructure Security

### Security Group

The security group is configured with **egress only** by default:

| Direction | Port | Source | Purpose |
|-----------|------|--------|---------|
| Outbound | All | `0.0.0.0/0` | Anthropic API, npm, Tailscale coordination |
| Inbound | 22 | `allowed_cidr` | SSH fallback (only if configured) |

No application ports (3100, 18789, 18800+) are exposed. Tailscale bypasses the security group entirely via its own encrypted tunnel.

### EC2 Instance Metadata

IMDSv2 is enforced (`http_tokens = "required"`). This prevents SSRF attacks from extracting IAM credentials via the metadata endpoint — a common attack vector in cloud environments.

### EBS Encryption

The root volume uses AWS-managed encryption (AES-256). All data at rest is encrypted, including:

- Paperclip database (embedded Postgres)
- OpenClaw agent configurations and auth profiles
- Agent workspaces and session data
- Master encryption key for Paperclip secrets

The volume has `delete_on_termination = false` to prevent accidental data loss on instance termination.

## Secrets Management

| Secret | Where it lives | How it's created |
|--------|---------------|-----------------|
| Anthropic API key | OpenClaw auth-profiles.json on disk | Passed via Terraform variable into user-data |
| Paperclip JWT secret | `~/.paperclip/instances/default/.env` | Generated at boot (`openssl rand -hex 32`) |
| Paperclip auth secret | `~/.paperclip/instances/default/.env` | Generated at boot (`openssl rand -hex 32`) |
| Paperclip master key | `~/.paperclip/instances/default/secrets/master.key` | Generated by `paperclipai onboard` |
| Gateway token | `openclaw-registry.json` + each `openclaw.json` | Auto-generated by Terraform or user-provided |
| Tailscale auth key | Used once during cloud-init, not stored | Passed via Terraform variable |

### Recommendations for production

- **Anthropic API key**: Store in [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) or [SSM Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html). Fetch during cloud-init instead of passing as a user-data variable.
- **Tailscale auth key**: Use an [ephemeral key](https://tailscale.com/kb/1085/auth-keys) so the device auto-removes from your tailnet when the instance is destroyed.
- **Terraform state**: Contains sensitive values. Use a [remote backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3) with encryption (S3 + DynamoDB) rather than local state files.

## What Is NOT Covered

This setup is designed for development and proof-of-concept use. The following are **not** included and should be considered for production:

- **TLS termination** — Paperclip serves HTTP. Traffic is encrypted by Tailscale in transit, but Paperclip itself does not terminate TLS. If you expose the instance beyond your tailnet, add a reverse proxy (Caddy, nginx) with TLS.
- **Backup automation** — EBS snapshots are not configured. Consider [AWS Backup](https://aws.amazon.com/backup/) or a lifecycle policy for daily snapshots.
- **Log aggregation** — Logs stay on the instance. For production, ship to CloudWatch, Datadog, or similar.
- **Intrusion detection** — No host-based IDS (OSSEC, etc.) is installed. fail2ban covers brute force SSH only.
- **Secret rotation** — Secrets generated at boot are not rotated. Implement rotation for long-running deployments.
- **Multi-user access control** — Paperclip has its own auth, but all Tailscale users with access to the device can reach all ports. Use Tailscale ACLs to restrict access if sharing the tailnet.
