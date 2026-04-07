# Paperclip + OpenClaw on AWS

Terraform configuration to deploy a [Paperclip](https://paperclipai.com) orchestration server with [OpenClaw](https://openclaw.dev) agent instances on a single EC2 instance, accessible securely via [Tailscale](https://tailscale.com).

Paperclip is an AI company orchestrator — it models a company org chart and delegates work to agents. OpenClaw provides the agent runtime: each agent gets its own persistent Claude Code session with full CLI/tool access. The CEO agent can hire new agents at runtime using a built-in skill.

## Architecture

```
                        Your Tailnet (WireGuard mesh)
                    ┌───────────────────────────────────┐
                    │                                   │
  ┌──────────┐     │    ┌─────────────────────────────────────────┐
  │ Your PC  │◄────┼───►│  EC2 Instance (Ubuntu 24.04)            │
  │ (browser)│     │    │                                         │
  └──────────┘     │    │  ┌──────────────┐  ┌────────────────┐   │
                    │    │  │  Paperclip   │  │ OpenClaw (CEO) │   │
                    │    │  │  :3100       │◄►│ :18800         │   │
                    │    │  │  + Postgres  │  ├────────────────┤   │
                    │    │  │              │◄►│ OpenClaw (CTO) │   │
                    │    │  │              │  │ :18801         │   │
                    │    │  │              │  ├────────────────┤   │
                    │    │  │              │◄►│ OpenClaw (...) │   │
                    │    │  └──────────────┘  │ :18802+        │   │
                    │    │                    └────────────────┘   │
                    │    └────────────────────────────┬────────────┘
                    └────────────────────────────────┘│
                                                      │ Anthropic API
                                                      │ :443
```

No ports are exposed to the public internet. All access goes through Tailscale's encrypted WireGuard mesh.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS CLI configured with credentials (`aws configure`)
- [Tailscale client](https://tailscale.com/download) installed and running on your local machine (verify with `tailscale status`)
- A [Tailscale auth key](https://login.tailscale.com/admin/settings/keys) (reusable recommended)
- An [Anthropic API key](https://console.anthropic.com/)

## Quick Start

```bash
# 1. Clone and enter the repo
git clone https://github.com/theunisdk/paperclip.git && cd paperclip

# 2. Create your config
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — you need: anthropic_api_key, tailscale_auth_key

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. Wait for setup (~5 min)
./scripts/logs.sh

# 5. Open the UI
./scripts/connect.sh
# Or just open http://paperclip:3100 in your browser
```

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in:

| Variable | Required | Description |
|----------|----------|-------------|
| `anthropic_api_key` | Yes | Anthropic API key (`sk-ant-...`) |
| `tailscale_auth_key` | Yes | Tailscale auth key (`tskey-auth-...`) |
| `tailscale_hostname` | No | Hostname on your tailnet (default: `paperclip`) |
| `aws_region` | No | AWS region (default: `us-east-1`) |
| `instance_type` | No | EC2 instance type (default: `t3.xlarge`) |
| `volume_size` | No | Root EBS volume in GB (default: `50`) |
| `paperclip_gateway_token` | No | Shared gateway token (auto-generated if empty) |
| `openclaw_agent_count` | No | Agent slot count (default: `4`) |
| `project_name` | No | AWS resource name prefix (default: `paperclip`) |
| `ssh_key_name` | No | AWS key pair for SSH fallback |
| `allowed_cidr` | No | CIDR for SSH fallback (only if `ssh_key_name` is set) |

### Generating a Tailscale Auth Key

1. Go to [Tailscale Admin > Settings > Keys](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Recommended settings: **Reusable** (so you can rebuild the instance), **Ephemeral** (auto-removes if instance is destroyed)
4. Copy the key into `terraform.tfvars`

### Instance Sizing

| Scale | Instance Type | vCPUs | RAM | Approx. Monthly Cost |
|-------|--------------|-------|-----|---------------------|
| Small (1 CEO + 3 agents) | `t3.xlarge` | 4 | 16 GB | ~$120 |
| Medium (1 CEO + 7 agents) | `t3.2xlarge` | 8 | 32 GB | ~$240 |
| Large (1 CEO + 15 agents) | `m6i.2xlarge` | 8 | 32 GB | ~$280 |

## Accessing the Server

Once deployed, the instance joins your Tailscale network automatically.

**Paperclip UI:**
```
http://paperclip:3100
```
(or whatever `tailscale_hostname` you set)

**SSH:**
```bash
ssh ubuntu@paperclip
```

Tailscale SSH is enabled (`--ssh`), so this works without managing SSH keys. Your Tailscale identity is used for authentication.

**No SSH tunnel needed.** No ports exposed to the internet. All traffic is encrypted via WireGuard.

## Helper Scripts

| Script | Purpose |
|--------|---------|
| `./scripts/connect.sh` | Check Tailscale connectivity and print the UI URL |
| `./scripts/status.sh` | Check service health, agent registry, and system resources |
| `./scripts/logs.sh` | Tail the cloud-init setup log |

## What Gets Deployed

- **VPC** with a public subnet (for outbound internet access)
- **Security group** — egress only, no inbound ports open (unless SSH fallback is configured)
- **EC2 instance** (Ubuntu 24.04) with encrypted gp3 EBS volume
- **Elastic IP** for stable outbound address
- **Tailscale** — joins your tailnet with the configured hostname and SSH enabled

The cloud-init user-data script installs and configures:
- Tailscale (first, so you can SSH in while the rest installs)
- Node.js 24, Paperclip (with drizzle-orm workaround), OpenClaw, Claude Code CLI
- Paperclip server in `authenticated` mode with embedded Postgres
- OpenClaw default instance (auth source for spawned agents)
- CEO workspace with `spawn-openclaw-agent` skill
- Systemd user service for auto-start

## How Agent Hiring Works

The CEO agent is pre-configured with a `spawn-openclaw-agent` skill that:

1. Reads the port registry to find the next available port
2. Creates a workspace directory for the new agent
3. Provisions an OpenClaw instance (`openclaw --profile <name> onboard ...`)
4. Copies auth credentials from the default instance
5. Starts the OpenClaw gateway
6. Sends initial persona/role instructions
7. Registers the agent in Paperclip as an `openclaw_gateway` adapter

All agents share a gateway token so Paperclip can connect to them on localhost.

## File Layout on EC2

```
/home/ubuntu/
├── paperclip-server/              # Paperclip npm install
├── paperclip-workspaces/          # All agent workspaces
│   ├── ceo/                       # CEO workspace + CLAUDE.md + skills
│   ├── openclaw-registry.json     # Port/instance registry
│   └── <agent-profile>/           # Created at runtime by CEO
├── .paperclip/instances/default/  # Paperclip config, DB, secrets
├── .openclaw/                     # Default OpenClaw instance (auth source)
├── .openclaw-<profile>/           # Per-agent OpenClaw profiles (runtime)
└── .config/systemd/user/          # Systemd service files
```

## Customizing the CEO

Edit [templates/ceo-claude.md](templates/ceo-claude.md) to change the CEO agent's system prompt and context. Edit [templates/spawn-openclaw-agent-skill.md](templates/spawn-openclaw-agent-skill.md) to modify how new agents are provisioned.

After changing templates, run `terraform apply` to rebuild the instance with updated user-data. Existing instances must be replaced (`terraform taint aws_instance.main` then `terraform apply`) since user-data only runs on first boot.

## Known Issues

- **drizzle-orm peer dependency**: Paperclip's `better-auth` needs `>=0.41.0` but bundles `0.38.4`. The setup installs `drizzle-orm@0.45.1` as a workaround. Check if newer Paperclip versions fix this.
- **OpenClaw auth-profiles.json**: Onboarding doesn't always populate the agent-level auth file. The spawn skill copies it from the default instance.
- **Memory pressure**: 4 active OpenClaw agents + Paperclip + Postgres need ~5–8 GB RAM. Use 16 GB minimum.

## Teardown

```bash
terraform destroy
```

This removes the EC2 instance and VPC but **not** the EBS volume (`delete_on_termination = false`). Delete it manually in the AWS Console (EC2 > Volumes) after confirming you don't need the data — **orphaned volumes incur storage charges** (~$0.08/GB/month for gp3).

The Tailscale device will auto-remove if you used an ephemeral auth key. Otherwise, remove it at [Tailscale Admin > Machines](https://login.tailscale.com/admin/machines).

## Security

See [docs/security.md](docs/security.md) for the full security overview.

**Network:**
- **No public ports** — security group allows egress only. All access via Tailscale.
- **Tailscale SSH** — no SSH keys to manage. Authentication via your Tailscale identity.
- **Tailscale ACLs** — control which tailnet users/devices can reach this instance.
- **UFW firewall** — denies all incoming except on the Tailscale interface and SSH fallback.

**OS hardening:**
- **SSH hardened** — root login disabled, password auth disabled, max 3 auth attempts.
- **fail2ban** — bans IPs after 3 failed SSH attempts for 1 hour.
- **Kernel hardening** — SYN flood protection, ICMP redirect rejection, source routing disabled, martian packet logging.
- **Automatic security updates** — `unattended-upgrades` enabled for daily patching.

**AWS:**
- **EBS encryption** — all data encrypted at rest.
- **IMDSv2 enforced** — prevents SSRF-based credential theft.
- **Secrets on disk** — JWT, auth, and master keys are generated at boot on the encrypted volume. The Anthropic API key is passed via user-data (consider AWS Secrets Manager for production).
