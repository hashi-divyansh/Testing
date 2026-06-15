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
        command = "/Users/divyansh/Desktop/Hashicorp/nomad-autoscaler/pkg/linux_arm64/nomad-autoscaler"
        args    = ["agent", "-config", "${NOMAD_TASK_DIR}/autoscaler.hcl"]
      }

      template {
        data = <<EOH
nomad {
  address = "http://server-vm-0.orb.local:4646"
}

# --- APM Plugins ---
# All plugins are loaded; the scaling policy (webapp-autoscale.nomad.hcl)
# selects which one to use via the `source` field.

apm "prometheus" {
  driver = "prometheus"
  config = {
    address = "http://prometheus-vm.orb.local:9090"
  }
}

apm "influxdb" {
  driver = "influxdb"
  config = {
    address       = "http://prometheus-vm.orb.local:8086"
    database      = "telegraf"
    username      = "autoscaler"
    shared_secret = "nomad-autoscaler-secret"
    token_ttl     = "1h"
  }
}

# apm "datadog" {
#   driver = "datadog"
#   config = {
#     address = "https://api.datadoghq.com"
#   }
# }

# apm "instana" {
#   driver = "instana"        # custom plugin — not yet built
#   config = {
#     endpoint  = "https://<unit>.instana.io"
#     api_token = "<token>"
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