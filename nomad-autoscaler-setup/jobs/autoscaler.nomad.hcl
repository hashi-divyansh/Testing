# jobs/autoscaler.nomad.hcl
#
# Runs nomad-autoscaler using the exec driver.
# Binary is sourced from nomad-autoscaler/pkg/linux_arm64/nomad-autoscaler
# which is mounted into OrbStack VMs at the same macOS path.
job "autoscaler" {
  datacenters = ["dc1"]
  type        = "service"

  group "autoscaler" {
    count = 1

    # Pin to a single client to avoid duplicate scaling decisions
    constraint {
      attribute = "${node.unique.name}"
      value     = "client-vm-0"
    }

    task "autoscaler" {
      driver = "exec"

      config {
        command = "AUTOSCALER_BIN_PLACEHOLDER"
        args    = ["agent", "-config", "${NOMAD_TASK_DIR}/autoscaler.hcl"]
      }

      # Instana credentials — injected at deploy time via `make deploy-autoscaler`.
      # Leave empty to disable Instana; set both to activate.
      env {
        INSTANA_ENDPOINT  = "INSTANA_ENDPOINT_PLACEHOLDER"
        INSTANA_API_TOKEN = "INSTANA_TOKEN_PLACEHOLDER"
      }

      template {
        data = <<EOH
nomad {
  address = "http://server-vm-0.orb.local:4646"
}

# --- APM Plugins ---
# All plugins are loaded at startup; the scaling policy (webapp-autoscale.nomad.hcl)
# selects which one to query via the `source` field in jobs/apm/*.nomad.vars.
# Switch APM with: make deploy-webapp APM=<prometheus|influxdb|instana>

apm "prometheus" {
  driver = "prometheus"
  config = {
    address = "http://prometheus.service.consul:9090"
  }
}

apm "influxdb" {
  driver = "influxdb"
  config = {
    address       = "http://influxdb.service.consul:8086"
    database      = "telegraf"
    username      = "autoscaler"
    shared_secret = "nomad-autoscaler-secret"
    token_ttl     = "1h"
  }
}

# Instana — rendered only when INSTANA_ENDPOINT env var is non-empty.
{{ with env "INSTANA_ENDPOINT" -}}
apm "instana" {
  driver = "instana"
  config = {
    endpoint  = "{{ . }}"
    api_token = "{{ env "INSTANA_API_TOKEN" }}"
  }
}
{{- end }}

# apm "datadog" — uncomment to enable.
# apm "datadog" {
#   driver = "datadog"
#   config = {
#     address = "https://api.datadoghq.com"
#   }
# }

# --- Strategies ---
strategy "target-value" {
  driver = "target-value"
}

strategy "threshold" {
  driver = "threshold"
}

strategy "fixed-value" {
  driver = "fixed-value"
}
EOH

        destination = "local/autoscaler.hcl"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}