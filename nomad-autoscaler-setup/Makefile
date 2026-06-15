.PHONY: provision terraform-init terraform-apply inventory ansible load-test destroy \
        deploy-autoscaler deploy-webapp deploy-backend teardown-backend

HEY_FLAGS     ?= -z 5m -c 100 -q 50
APM           ?= prometheus
AUTOSCALER_BIN ?= $(HOME)/Desktop/Hashicorp/nomad-autoscaler/pkg/linux_arm64/nomad-autoscaler
INSTANA_ENDPOINT ?=
INSTANA_TOKEN    ?=

provision: terraform-init terraform-apply inventory ansible

terraform-init:
	terraform init

terraform-apply:
	terraform apply -auto-approve

inventory:
	python3 ansible/inventory/generate_inventory.py

ansible: inventory
	ANSIBLE_CONFIG=ansible/ansible.cfg ANSIBLE_ROLES_PATH=ansible/roles ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml

# Deploy the autoscaler job (exec driver, binary path set by AUTOSCALER_BIN).
# Override: make deploy-autoscaler AUTOSCALER_BIN=/path/to/nomad-autoscaler
# Instana:  make deploy-autoscaler INSTANA_ENDPOINT=https://<unit>.instana.io INSTANA_TOKEN=<token>
deploy-autoscaler:
	sed -e "s|AUTOSCALER_BIN_PLACEHOLDER|$(AUTOSCALER_BIN)|g" \
	    -e "s|INSTANA_ENDPOINT_PLACEHOLDER|$(INSTANA_ENDPOINT)|g" \
	    -e "s|INSTANA_TOKEN_PLACEHOLDER|$(INSTANA_TOKEN)|g" \
	    jobs/autoscaler.nomad.hcl | nomad job run -

# Deploy an APM backend as a Nomad Docker job.
# Usage: make deploy-backend APM=prometheus
#        make deploy-backend APM=influxdb
# Available backends: prometheus | influxdb
deploy-backend:
	@if [ ! -f jobs/backends/$(APM).nomad.hcl ]; then \
		echo "ERROR: No backend job found for APM '$(APM)'. Available:"; \
		ls jobs/backends/*.nomad.hcl | xargs -n1 basename | sed 's/.nomad.hcl//'; \
		exit 1; \
	fi
	nomad job run jobs/backends/$(APM).nomad.hcl
	@if [ "$(APM)" = "influxdb" ]; then \
		echo "Also deploying telegraf (metrics collector for influxdb)..."; \
		nomad job run jobs/backends/telegraf.nomad.hcl; \
	fi

# Stop and purge an APM backend.
# Usage: make teardown-backend APM=prometheus
teardown-backend:
	nomad job stop -purge $(APM) 2>/dev/null || true
	@if [ "$(APM)" = "influxdb" ]; then \
		nomad job stop -purge telegraf 2>/dev/null || true; \
	fi

# Deploy the webapp with a specific APM source.
# Usage: make deploy-webapp APM=influxdb
# Available: prometheus | influxdb | instana | datadog
deploy-webapp:
	@if [ ! -f jobs/apm/$(APM).nomad.vars ]; then \
		echo "ERROR: No var file found for APM '$(APM)'. Available:"; \
		ls jobs/apm/*.nomad.vars | xargs -n1 basename | sed 's/.nomad.vars//'; \
		exit 1; \
	fi
	nomad job run -var-file=jobs/apm/$(APM).nomad.vars jobs/webapp-autoscale.nomad.hcl

load-test:
	@if ! command -v hey >/dev/null 2>&1; then \
		echo "hey is not installed. Install with: brew install hey"; \
		exit 1; \
	fi
	@if [ -z "$(WEBAPP_URL)" ]; then \
		echo "Set WEBAPP_URL to the webapp allocation URL"; \
		echo "Example: make load-test WEBAPP_URL=http://192.168.139.135:28915"; \
		exit 1; \
	fi
	hey $(HEY_FLAGS) "$(WEBAPP_URL)"

destroy:
	terraform destroy -auto-approve