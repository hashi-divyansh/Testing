.PHONY: provision terraform-init terraform-apply inventory ansible load-test destroy \
        deploy-autoscaler deploy-webapp

HEY_FLAGS ?= -z 5m -c 100 -q 50
APM       ?= prometheus

provision: terraform-init terraform-apply inventory ansible

terraform-init:
	terraform init

terraform-apply:
	terraform apply -auto-approve

inventory:
	python3 ansible/inventory/generate_inventory.py

ansible: inventory
	ANSIBLE_CONFIG=ansible/ansible.cfg ANSIBLE_ROLES_PATH=ansible/roles ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/site.yml

# Deploy the autoscaler job (exec driver, binary from nomad-autoscaler/pkg/linux_arm64/)
deploy-autoscaler:
	nomad job run jobs/autoscaler.nomad.hcl

# Deploy the webapp with a specific APM plugin.
# Usage: make deploy-webapp APM=influxdb
# Available: prometheus | influxdb | datadog | instana
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