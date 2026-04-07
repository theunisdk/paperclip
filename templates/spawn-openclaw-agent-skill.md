---
name: spawn-openclaw-agent
description: >
  Spawn a new OpenClaw agent instance and register it in Paperclip. Use when
  hiring a new agent that needs autonomy — i.e. its own OpenClaw gateway
  instance with full CLI/tool access, rather than a simple claude_local adapter.
  This skill handles: provisioning the OpenClaw profile, starting the gateway,
  sending initial persona/instructions, and registering the agent in Paperclip
  as an openclaw_gateway adapter.
---

# Spawn OpenClaw Agent Skill

Use this skill when you need to hire a new agent that should run as an
autonomous OpenClaw instance connected to Paperclip.

## When to Use

- You are asked to hire/create a new agent
- The agent needs autonomy, persistent sessions, or its own tool environment
- You want the agent to run as a dedicated OpenClaw instance

## When NOT to Use

- For simple one-shot tasks (use claude_local instead)
- When the system is running low on resources
- When you already have an idle OpenClaw agent that could be reassigned

## Prerequisites

- `openclaw` CLI installed globally
- An Anthropic API key (set as `ANTHROPIC_API_KEY` env var or read from default instance)
- Paperclip API accessible at `$PAPERCLIP_API_URL`

## Constants

- **Shared gateway token**: Read from `/home/ubuntu/paperclip-workspaces/openclaw-registry.json` field `sharedToken`
- **Port registry file**: `/home/ubuntu/paperclip-workspaces/openclaw-registry.json`
- **Base port**: `18800` (instances use 18800, 18801, 18802, ...)
- **Workspaces root**: `/home/ubuntu/paperclip-workspaces`
- **Auth source**: `/home/ubuntu/.openclaw/agents/main/agent/auth-profiles.json`

## Workflow

### Step 1: Read the Registry and Determine Next Port

```bash
REGISTRY_FILE="/home/ubuntu/paperclip-workspaces/openclaw-registry.json"
if [ ! -f "$REGISTRY_FILE" ]; then
  echo '{"instances":[]}' > "$REGISTRY_FILE"
fi
cat "$REGISTRY_FILE"
```

Next port = 18800 + number of existing instances.
Profile name = short kebab-case role identifier.

### Step 2: Create Workspace Directory

```bash
AGENT_PROFILE="<profile-name>"
WORKSPACE_DIR="/home/ubuntu/paperclip-workspaces/$AGENT_PROFILE"
mkdir -p "$WORKSPACE_DIR"
```

### Step 3: Provision the OpenClaw Instance

Read the API key from the default instance auth-profiles:

```bash
ANTHROPIC_API_KEY=$(python3 -c "
import json
with open('/home/ubuntu/.openclaw/agents/main/agent/auth-profiles.json') as f:
    data = json.load(f)
for k, v in data.get('profiles', {}).items():
    if v.get('provider') == 'anthropic' and 'token' in v:
        print(v['token'])
        break
")
```

Read the shared token from the registry:

```bash
SHARED_TOKEN=$(python3 -c "
import json
with open('/home/ubuntu/paperclip-workspaces/openclaw-registry.json') as f:
    print(json.load(f)['sharedToken'])
")
```

Run onboarding:

```bash
openclaw --profile "$AGENT_PROFILE" onboard \
  --non-interactive \
  --accept-risk \
  --auth-choice apiKey \
  --anthropic-api-key "$ANTHROPIC_API_KEY" \
  --gateway-bind lan \
  --gateway-auth token \
  --gateway-token "$SHARED_TOKEN" \
  --gateway-port <PORT> \
  --workspace "$WORKSPACE_DIR" \
  --skip-channels \
  --skip-skills \
  --skip-search \
  --skip-ui \
  --install-daemon
```

Copy auth profile (onboarding does not always populate the agent-level auth):

```bash
PROFILE_DIR="/home/ubuntu/.openclaw-${AGENT_PROFILE}/agents/main/agent"
mkdir -p "$PROFILE_DIR"
cp /home/ubuntu/.openclaw/agents/main/agent/auth-profiles.json \
   "$PROFILE_DIR/auth-profiles.json"
```

Start the gateway:

```bash
openclaw --profile "$AGENT_PROFILE" gateway --force &
sleep 5
```

### Step 4: Verify

```bash
openclaw --profile "$AGENT_PROFILE" health
```

### Step 5: Send Initial Persona

```bash
openclaw --profile "$AGENT_PROFILE" agent \
  --message "Your name is <AGENT_NAME>. Your role is <ROLE_TITLE>.
<PERSONA_AND_INSTRUCTIONS>
You are part of a Paperclip-orchestrated company.
Your workspace is at $WORKSPACE_DIR.
Acknowledge that you understand your role." \
  --thinking medium
```

### Step 6: Update Registry

```bash
cat "$REGISTRY_FILE" | python3 -c "
import json, sys
reg = json.load(sys.stdin)
reg['instances'].append({
    'profile': '$AGENT_PROFILE',
    'port': <PORT>,
    'name': '<AGENT_NAME>',
    'role': '<ROLE_TITLE>',
    'workspace': '$WORKSPACE_DIR',
    'status': 'running',
    'createdAt': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
})
print(json.dumps(reg, indent=2))
" > "${REGISTRY_FILE}.tmp" && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"
```

### Step 7: Register in Paperclip

```bash
curl -sS -X POST "$PAPERCLIP_API_URL/api/companies/$PAPERCLIP_COMPANY_ID/agent-hires" \
  -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
  -H "Content-Type: application/json" \
  -H "X-Paperclip-Run-Id: $PAPERCLIP_RUN_ID" \
  -d '{
    "name": "<AGENT_NAME>",
    "role": "<role>",
    "title": "<Role Title>",
    "icon": "<icon>",
    "reportsTo": "<your-agent-id>",
    "capabilities": "<capabilities>",
    "adapterType": "openclaw_gateway",
    "adapterConfig": {
      "url": "ws://127.0.0.1:<PORT>",
      "authToken": "<SHARED_TOKEN>",
      "sessionKeyStrategy": "issue",
      "timeoutSec": 600,
      "waitTimeoutMs": 590000
    },
    "runtimeConfig": {
      "heartbeat": {
        "enabled": true,
        "intervalSec": 300,
        "wakeOnDemand": true
      }
    }
  }'
```

Look up your agent ID via `GET /api/agents/me` first.
Pick an icon from `GET /llms/agent-icons.txt`.

### Step 8: Handle Approval

Follow the standard paperclip-create-agent approval workflow.

## Managing Instances

- List all: `cat /home/ubuntu/paperclip-workspaces/openclaw-registry.json`
- Health check: `openclaw --profile <name> health`
- Restart: `openclaw --profile <name> gateway --force &`
- Send message: `openclaw --profile <name> agent --message "<msg>"`

## Troubleshooting

- Port in use: use `--force` or increment port
- Gateway won't start: `openclaw --profile <name> doctor`
- Auth errors: verify auth-profiles.json was copied from default instance
- No API key: check `/home/ubuntu/.openclaw/agents/main/agent/auth-profiles.json`
