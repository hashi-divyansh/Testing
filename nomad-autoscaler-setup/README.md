# Nomad Autoscaler Setup with OrbStack

Local learning cluster for Nomad Autoscaler on OrbStack VMs. Provisions a 6-node Nomad+Consul cluster via Terraform + Ansible, then runs APM backends and the autoscaler as Nomad jobs.

## Architecture

```
Terraform: 3 server VMs + 3 client VMs (Debian ARM64)
│
├── Consul  — service discovery on all nodes (*.service.consul DNS)
├── Nomad   — servers on server-vm-{0,1,2}, clients on client-vm-{0,1,2}
│
└── Nomad jobs (deployed after cluster is up):
    ├── autoscaler      — exec driver, binary from nomad-autoscaler/pkg/linux_arm64/
    ├── webapp          — nginx, scaled by autoscaler
    ├── load-balancer   — HAProxy, routes to webapp via Consul
    ├── prometheus      — Prometheus, scrapes Nomad metrics → prometheus.service.consul:9090
    ├── influxdb        — InfluxDB 1.8, stores Telegraf metrics → influxdb.service.consul:8086
    └── telegraf        — system job (1 per client node), pushes host metrics to InfluxDB
```

## Prerequisites

- macOS with [OrbStack](https://orbstack.dev)
- `terraform`, `ansible`, `python3`, `nomad` CLI
- SSH key pair at `~/.ssh/id_ed25519`

## Quick Start

```bash
# 1. Provision cluster (creates VMs + configures all nodes)
make provision

# 2. Start the autoscaler
make deploy-autoscaler

# 3. Start an APM backend (choose one)
make deploy-backend APM=prometheus   # Prometheus + Nomad metrics
make deploy-backend APM=influxdb     # InfluxDB + Telegraf (host metrics)

# 4. Deploy the webapp, scaled by the chosen APM
make deploy-webapp APM=prometheus    # or influxdb

# 5. Deploy load balancer
nomad job run jobs/load-balancer.nomad.hcl

# 6. Run a load test
make load-test WEBAPP_URL=http://localhost:8080
```

## Switching APM at Any Time

The autoscaler loads all APM plugin drivers on startup. Switch the webapp's APM source without restarting the autoscaler:

```bash
make deploy-webapp APM=influxdb     # switch to InfluxDB
make deploy-webapp APM=prometheus   # switch back to Prometheus
```

Var files in `jobs/apm/` define the source, query, and target for each APM.

## Custom Autoscaler Binary

By default, `make deploy-autoscaler` uses:
```
$(HOME)/Desktop/Hashicorp/nomad-autoscaler/pkg/linux_arm64/nomad-autoscaler
```

Override:
```bash
make deploy-autoscaler AUTOSCALER_BIN=/path/to/your/nomad-autoscaler
```

Build from source:
```bash
cd ~/Desktop/Hashicorp/nomad-autoscaler
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o pkg/linux_arm64/nomad-autoscaler .
```

## Access UIs

| Service | URL |
|---|---|
| Nomad | http://localhost:4646/ui/jobs |
| Consul | http://server-vm-0.orb.local:8500/ui |
| HAProxy stats | http://localhost:1936 |

> Use `localhost` in the browser — Chrome blocks `.orb.local`. `.orb.local` works in CLI tools.

## Makefile Reference

| Target | Description |
|---|---|
| `make provision` | Full cluster setup (Terraform + inventory + Ansible) |
| `make deploy-autoscaler` | Deploy the autoscaler job |
| `make deploy-backend APM=<name>` | Start an APM backend (`prometheus` or `influxdb`) |
| `make teardown-backend APM=<name>` | Stop and purge an APM backend |
| `make deploy-webapp APM=<name>` | Deploy webapp with chosen APM source |
| `make load-test WEBAPP_URL=<url>` | Run HTTP load test via `hey` |
| `make destroy` | Destroy all VMs |

## Supported APM Plugins

| APM | Backend | Notes |
|---|---|---|
| `prometheus` | `jobs/backends/prometheus.nomad.hcl` | Scrapes Nomad telemetry |
| `influxdb` | `jobs/backends/influxdb.nomad.hcl` + `telegraf.nomad.hcl` | InfluxDB 1.x + Telegraf host metrics |
| `instana` | External SaaS / self-hosted | Inject creds at deploy time — see below |
| `datadog` | External SaaS | Uncomment block in `autoscaler.nomad.hcl` |

### Enabling Instana

No backend job needed — Instana runs externally. Pass credentials at deploy time:

```bash
# Deploy autoscaler with Instana enabled
make deploy-autoscaler \
  INSTANA_ENDPOINT=https://<unit>.instana.io \
  INSTANA_TOKEN=<your-api-token>

# Then deploy the webapp using the instana var file
make deploy-webapp APM=instana
```

The autoscaler config uses a Go template conditional — if `INSTANA_ENDPOINT` is empty (the default), the Instana APM block is not rendered and the plugin is not loaded. Re-deploy with the endpoint set to activate it.

The `jobs/apm/instana.nomad.vars` query format uses Instana's infrastructure metrics API body:
```hcl
apm_query = "{\"plugin\":\"host\",\"metrics\":[\"cpu.user\"]}"
```

## Project Structure

```
nomad-autoscaler-setup/
├── main.tf                          # Terraform: 3 server + 3 client OrbStack VMs
├── cloud-init-bootstrap.yaml.tmpl   # Minimal SSH + Python bootstrap
├── Makefile                         # All operational targets
├── ansible/
│   ├── ansible.cfg
│   ├── group_vars/all.yml           # Shared vars (Consul + Nomad versions)
│   ├── inventory/
│   │   ├── generate_inventory.py    # Reads Terraform outputs → hosts.yml
│   │   └── hosts.yml                # Auto-generated (gitignored)
│   ├── playbooks/site.yml           # base → consul (all nodes) → nomad_server → nomad_client
│   └── roles/
│       ├── base/                    # Common deps + /etc/hosts + DNS resolver
│       ├── consul/                  # Consul agent (server + client mode via when:)
│       ├── nomad_server/            # Nomad server + systemd unit
│       └── nomad_client/            # Nomad client + Docker + host_volume
└── jobs/
    ├── autoscaler.nomad.hcl         # Autoscaler (exec driver, configurable binary)
    ├── webapp-autoscale.nomad.hcl   # Webapp with variable APM scaling policy
    ├── load-balancer.nomad.hcl      # HAProxy with Consul template
    ├── apm/                         # Var files per APM: prometheus | influxdb | instana | datadog
    └── backends/                    # Backend jobs: prometheus | influxdb | telegraf
```

## Troubleshooting

```bash
# Re-generate inventory after VM restart (IPs change every time)
make inventory && make ansible

# Check cluster health
orb run -m server-vm-0 nomad server members
orb run -m server-vm-0 nomad node status

# Follow autoscaler logs
nomad alloc logs -f $(nomad job allocs -t '{{range .}}{{.ID}}{{end}}' autoscaler)

# Ping all nodes
ANSIBLE_CONFIG=ansible/ansible.cfg ansible -i ansible/inventory/hosts.yml all -m ping
```
