# jobs/webapp-autoscale.nomad.hcl
#
# APM source is configurable via var files in jobs/apm/.
# Usage:
#   nomad job run -var-file=jobs/apm/prometheus.nomad.vars jobs/webapp-autoscale.nomad.hcl
#   nomad job run -var-file=jobs/apm/influxdb.nomad.vars   jobs/webapp-autoscale.nomad.hcl
#
# Or via Makefile:
#   make deploy-webapp APM=influxdb

variable "apm_source" {
  type        = string
  default     = "prometheus"
  description = "APM plugin to use: prometheus | influxdb | datadog"
}

variable "apm_query" {
  type        = string
  default     = "max_over_time(nomad_client_allocs_cpu_total_percent{task='web'}[1m])"
  description = "APM query string for the selected source"
}

variable "scale_target" {
  type        = number
  default     = 50
  description = "Target value for the scaling strategy (e.g. CPU %)"
}

job "webapp" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    count = 1

    scaling {
      enabled = true
      min     = 1
      max     = 10

      policy {
        cooldown            = "30s"
        evaluation_interval = "10s"

        check "cpu_usage" {
          source = var.apm_source
          query  = var.apm_query

          strategy "target-value" {
            target = var.scale_target
          }
        }
      }
    }

    network {
      port "http" {
        to = 80
      }
    }

    service {
      name     = "webapp"
      port     = "http"
      provider = "consul"

      tags = ["load-balancer", "http", "web"]

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
        method   = "GET"
      }

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "web" {
      driver = "docker"

      config {
        image = "nginx:alpine"
        ports = ["http"]
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}