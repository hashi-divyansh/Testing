# jobs/backends/telegraf.nomad.hcl
#
# Runs Telegraf as a Nomad SYSTEM job (Docker) — one allocation per Nomad client node.
# Collects host CPU/mem/disk/net metrics and writes to InfluxDB.
# Requires: influxdb backend job running (influxdb.service.consul:8086)
#
# Deploy:  nomad job run jobs/backends/telegraf.nomad.hcl
#          (automatically deployed by: make deploy-backend APM=influxdb)

job "telegraf" {
  datacenters = ["dc1"]
  type        = "system"

  group "telegraf" {

    task "telegraf" {
      driver = "docker"

      config {
        image        = "telegraf:1.30"
        network_mode = "host"
        privileged   = true
        volumes = [
          "/proc:/host/proc:ro",
          "/sys:/host/sys:ro",
          "/:/host/rootfs:ro",
          "local/telegraf.conf:/etc/telegraf/telegraf.conf:ro",
        ]
      }

      # Telegraf config — uses Consul DNS to discover InfluxDB.
      # Collecting core host metrics for autoscaler CPU-based scaling.
      template {
        data = <<EOH
[agent]
  interval         = "10s"
  round_interval   = true
  flush_interval   = "10s"
  flush_jitter     = "2s"
  omit_hostname    = false

[[inputs.cpu]]
  percpu      = false
  totalcpu    = true
  collect_cpu_time = false
  report_active    = false

[[inputs.mem]]

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.diskio]]

[[inputs.net]]
  ignore_protocol_stats = true

[[inputs.system]]

[[outputs.influxdb]]
  urls             = ["http://influxdb.service.consul:8086"]
  database         = "telegraf"
  username         = "telegraf"
  password         = "telegraf_password"
  skip_database_creation = true
EOH
        destination = "local/telegraf.conf"
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }
}
