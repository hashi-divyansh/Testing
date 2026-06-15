#!/usr/bin/env python3

import json
import os
import subprocess
import sys
from pathlib import Path


def terraform_outputs(terraform_dir: Path) -> dict:
    result = subprocess.run(
        ["terraform", f"-chdir={terraform_dir}", "output", "-json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def get_value(outputs: dict, key: str, default):
    output = outputs.get(key)
    if not output:
        return default
    return output.get("value", default)


def host_map(nodes):
    hosts = {}
    for node in nodes:
        name = node["name"]
        hosts[name] = {
            "ansible_host": node["ssh_host"],
            "ansible_port": node["ssh_port"],
        }
    return hosts


def main() -> int:
    script_dir = Path(__file__).resolve().parent
    ansible_dir = script_dir.parent
    project_root = ansible_dir.parent

    try:
        outputs = terraform_outputs(project_root)
    except subprocess.CalledProcessError as exc:
        print("Failed to read Terraform outputs. Run terraform apply first.", file=sys.stderr)
        print(exc.stderr, file=sys.stderr)
        return exc.returncode or 1

    servers = get_value(outputs, "server_vm_connections", [])
    clients = get_value(outputs, "client_vm_connections", [])
    ansible_user = os.getenv("ANSIBLE_USER", "root")
    ansible_key = os.getenv("ANSIBLE_PRIVATE_KEY_FILE", "~/.ssh/id_ed25519")

    inventory = {
        "all": {
            "vars": {
                "ansible_user": ansible_user,
                "ansible_ssh_private_key_file": ansible_key,
            },
            "children": {
                "nomad_servers": {
                    "hosts": host_map(servers),
                },
                "nomad_clients": {
                    "hosts": host_map(clients),
                },
            }
        }
    }

    hosts_path = script_dir / "hosts.yml"
    hosts_path.write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")

    print(f"Inventory generated at {hosts_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
