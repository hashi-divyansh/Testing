# jobs/backends/prometheus.nomad.hcl
#
# Runs Prometheus as a Nomad service job (Docker).
# Registers with Consul as: prometheus.service.consul:9090
#
# Deploy:  nomad job run jobs/backends/prometheus.nomad.hcl
#          OR: make deploy-backend APM=prometheus

job "prometheus" {
  datacenters = ["dc1"]
  type        = "service"

  group "prometheus" {
    count = 1

    network {
      port "http" {
        static = 9090
      }
    }

    service {
      name = "prometheus"
      port = "http"
      tags = ["apm", "prometheus"]

      check {
        type     = "http"
        path     = "/-/healthy"
        interval = "15s"
        timeout  = "3s"
      }
    }

    task "prometheus" {
      driver = "docker"

      config {
        image = "prom/prometheus:latest"
        ports = ["http"]
        args  = ["--config.file=/etc/prometheus/prometheus.yml", "--storage.tsdb.retention.time=7d"]
        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml",
        ]
      }

      # Prometheus scrape config — targets Nomad server and client metrics endpoints.
      # OrbStack .orb.local DNS resolves inside containers.
      template {
        data = <<EOH
global:
  scrape_interval:     15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: "nomad-servers"
    static_configs:
      - targets:
          - "server-vm-0.orb.local:4646"
          - "server-vm-1.orb.local:4646"
          - "server-vm-2.orb.local:4646"
    metrics_path: "/v1/metrics"
    params:
      format: ["prometheus"]

  - job_name: "nomad-clients"
    static_configs:
      - targets:
          - "client-vm-0.orb.local:4646"
          - "client-vm-1.orb.local:4646"
          - "client-vm-2.orb.local:4646"
    metrics_path: "/v1/metrics"
    params:
      format: ["prometheus"]
EOH
        destination = "local/prometheus.yml"
        change_mode = "signal"
        change_signal = "SIGHUP"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
