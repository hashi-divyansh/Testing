# jobs/backends/influxdb.nomad.hcl
#
# Runs InfluxDB 1.8 as a Nomad service job (Docker).
# Pinned to client-vm-0 and uses a host_volume for data persistence.
# Registers with Consul as: influxdb.service.consul:8086
#
# Requires: host_volume "influxdb-data" defined on client-vm-0 (see ansible client role).
#
# Deploy:  nomad job run jobs/backends/influxdb.nomad.hcl
#          OR: make deploy-backend APM=influxdb  (also deploys telegraf)

job "influxdb" {
  datacenters = ["dc1"]
  type        = "service"

  group "influxdb" {
    count = 1

    # Pin to client-vm-0 so the host_volume always holds the data.
    constraint {
      attribute = "${node.unique.name}"
      value     = "client-vm-0"
    }

    volume "influxdb-data" {
      type      = "host"
      source    = "influxdb-data"
      read_only = false
    }

    network {
      port "http" {
        static = 8086
      }
    }

    service {
      name = "influxdb"
      port = "http"
      tags = ["apm", "influxdb"]

      check {
        type     = "http"
        path     = "/ping"
        interval = "15s"
        timeout  = "3s"
      }
    }

    # Main InfluxDB task
    task "influxdb" {
      driver = "docker"

      config {
        image = "influxdb:1.8"
        ports = ["http"]
      }

      volume_mount {
        volume      = "influxdb-data"
        destination = "/var/lib/influxdb"
        read_only   = false
      }

      env {
        INFLUXDB_HTTP_AUTH_ENABLED  = "true"
        INFLUXDB_HTTP_SHARED_SECRET = "nomad-autoscaler-secret"
        INFLUXDB_DB                 = "telegraf"
        INFLUXDB_ADMIN_USER         = "admin"
        INFLUXDB_ADMIN_PASSWORD     = "admin_secure_password"
      }

      resources {
        cpu    = 200
        memory = 512
      }
    }

    # Init task — runs once after InfluxDB starts to create application users.
    # Uses lifecycle poststart so it runs after the main task is healthy.
    task "influxdb-init" {
      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      driver = "docker"

      config {
        image   = "influxdb:1.8"
        command = "/bin/sh"
        args = ["-c", <<CMD
set -e
INFLUX="influx -host influxdb.service.consul -port 8086 -username admin -password admin_secure_password"

# Wait for InfluxDB to accept connections
echo "Waiting for InfluxDB..."
until $INFLUX -execute "SHOW DATABASES" > /dev/null 2>&1; do
  sleep 2
done
echo "InfluxDB ready."

# Create telegraf user (WRITE on telegraf db)
$INFLUX -execute "CREATE USER telegraf WITH PASSWORD 'telegraf_password'" 2>/dev/null || true
$INFLUX -execute "GRANT WRITE ON telegraf TO telegraf"                    2>/dev/null || true

# Create autoscaler user (READ on telegraf db)
$INFLUX -execute "CREATE USER autoscaler WITH PASSWORD 'autoscaler_password'" 2>/dev/null || true
$INFLUX -execute "GRANT READ ON telegraf TO autoscaler"                       2>/dev/null || true

echo "InfluxDB users configured."
CMD
        ]
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
