"""Load, validate, and export the Alpha5 control-plane settings.

The console writes config/platform.json and regenerates the Ansible inventory,
group variables, Terraform auto.tfvars, HTTP checks, and GitHub Actions workflow.
Token secrets and kubeconfigs are never stored here.
"""

from __future__ import annotations

import json
import os
import re
import threading
from pathlib import Path

import database

REPO = Path(os.environ.get("ALPHA5_REPO", Path(__file__).resolve().parent.parent))
CONFIG_PATH = REPO / "config" / "platform.json"
ENVIRONMENTS = ("dev", "staging", "prod")
LOCK = threading.Lock()

NAME = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
USER = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
HOST = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")
IPV4 = re.compile(r"^(?:\d{1,3}\.){3}\d{1,3}$")
CIDR = re.compile(r"^(?:\d{1,3}\.){3}\d{1,3}/\d{1,2}$")
CPU = re.compile(r"^(?:[1-9]\d*m|[1-9]\d*)$")
MEMORY = re.compile(r"^[1-9]\d*(?:Ki|Mi|Gi)$")
TAG = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
IMAGE = re.compile(r"^[a-z0-9]+(?:[._/-][a-z0-9]+)*$")
PACKAGE = re.compile(r"^[a-z0-9][a-z0-9+._-]{0,62}$")
ENV_KEY = re.compile(r"^[A-Z_][A-Z0-9_]{0,63}$")
CRON_FIELD = re.compile(r"^(?:\*|\*/[1-9]\d?|\d{1,2}(?:-\d{1,2})?(?:,\d{1,2}(?:-\d{1,2})?)*)$")
REL_PATH = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_./-]{0,119}$")
BRANCH = re.compile(r"^[A-Za-z0-9._/-]{1,80}$")
REGISTRY = re.compile(r"^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$")
KEY_PATH = re.compile(r"^(?:~|\.|[A-Za-z]:)?[/\\A-Za-z0-9._-]{1,180}$")
URL = re.compile(r"^https?://[A-Za-z0-9.-]+(?::\d{1,5})?(?:/[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]*)?$")

INSTALL_METHODS = ("kubeadm", "k3s", "rke2")
RUNTIMES = ("containerd", "docker")
CNIS = ("flannel", "calico", "weave")
ROLES = ("control_plane", "worker")
SCOPES = ("all", "control_plane", "workers")
ACTIONS = {
    "unattended-upgrades": "/usr/bin/unattended-upgrade -d",
    "apt-upgrade": "/usr/bin/apt-get update && /usr/bin/apt-get upgrade -y",
}
SERVICE_TYPES = ("ClusterIP", "NodePort", "LoadBalancer")


class ConfigError(ValueError):
    """The submitted settings failed validation."""


def repo_ready() -> bool:
    return (REPO / "terraform").is_dir() and (REPO / "ansible").is_dir()


def generated_paths() -> list[str]:
    paths = [
        "config/platform.json",
        "ansible/inventory.yml",
        "ansible/group_vars/platform.yml",
        "monitoring/http-checks.yml",
        ".github/workflows/deploy.yml",
    ]
    paths.extend(f"environments/{env}/platform.auto.tfvars.json" for env in ENVIRONMENTS)
    return paths


def default_config() -> dict:
    return {
        "proxmox": {
            "api_host": "",
            "api_user": "root@pam",
            "token_id": "",
            "node": "pve",
            "storage": "local-lvm",
            "bridge": "vmbr0",
            "template": "ubuntu-2204",
            "cidr_prefix": 24,
            "gateway": "",
            "nameserver": "1.1.1.1",
        },
        "cluster": {
            "name": "alpha5",
            "install_method": "kubeadm",
            "kubernetes_version": "1.34.0",
            "container_runtime": "containerd",
            "cni_plugin": "flannel",
            "pod_network_cidr": "10.245.0.0/16",
            "service_cidr": "10.96.0.0/12",
            "ansible_user": "support",
            "ssh_private_key_file": "~/.ssh/id_rsa",
        },
        "hosts": [
            _host("master1", "192.168.10.73", "control_plane", "devops1-cluster"),
            _host("worker1", "192.168.10.74", "worker", "devops2-cluster"),
            _host("worker2", "192.168.10.75", "worker", "devops3-cluster"),
        ],
        "software": [
            {"name": "containerd", "version": "latest", "scope": "all"},
            {"name": "chrony", "version": "latest", "scope": "all"},
            {"name": "unattended-upgrades", "version": "latest", "scope": "all"},
            {"name": "helm", "version": "latest", "scope": "control_plane"},
            {"name": "prometheus-node-exporter", "version": "latest", "scope": "all"},
        ],
        "updates": [
            {
                "name": "security-weekly",
                "cron": "0 3 * * 0",
                "scope": "all",
                "action": "unattended-upgrades",
                "enabled": True,
            },
            {
                "name": "package-monthly",
                "cron": "0 4 1 * *",
                "scope": "all",
                "action": "apt-upgrade",
                "enabled": False,
            },
        ],
        "monitoring": {
            "environments": ["dev"],
            "grafana": True,
            "grafana_ingress": True,
            "grafana_host": "grafana.alpha5.finance",
            "checks": [],
        },
        "services": {
            "dev": [
                _service("api-service", "alpha5/api-service", "latest", 2, "100m", "128Mi", "500m", "512Mi", 8080, "api-dev.example.com", [
                    ("ENVIRONMENT", "development"), ("LOG_LEVEL", "debug"), ("DB_HOST", "dev-db.example.com"),
                ]),
                _service("web-app", "alpha5/web-app", "latest", 2, "100m", "128Mi", "500m", "512Mi", 3000, "app-dev.example.com", [
                    ("ENVIRONMENT", "development"), ("API_URL", "http://api-service-service:8080"),
                ]),
            ],
            "staging": [
                _service("api-service", "alpha5/api-service", "v1.0.0", 3, "200m", "256Mi", "1000m", "1Gi", 8080, "api-staging.example.com", [
                    ("ENVIRONMENT", "staging"), ("LOG_LEVEL", "info"), ("DB_HOST", "staging-db.example.com"),
                ]),
                _service("web-app", "alpha5/web-app", "v1.0.0", 3, "200m", "256Mi", "1000m", "1Gi", 3000, "app-staging.example.com", [
                    ("ENVIRONMENT", "staging"), ("API_URL", "http://api-service-service:8080"),
                ]),
            ],
            "prod": [
                _service("api-service", "alpha5/api-service", "v1.0.0", 5, "500m", "512Mi", "2000m", "2Gi", 8080, "api.example.com", [
                    ("ENVIRONMENT", "production"), ("LOG_LEVEL", "warn"), ("DB_HOST", "prod-db.example.com"),
                ]),
                _service("web-app", "alpha5/web-app", "v1.0.0", 5, "500m", "512Mi", "2000m", "2Gi", 3000, "app.example.com", [
                    ("ENVIRONMENT", "production"), ("API_URL", "http://api-service-service:8080"),
                ]),
            ],
        },
        "cicd": {
            "registry": "ghcr.io",
            "branches": {"dev": "develop", "staging": "release", "prod": "main"},
            "pipelines": [
                {
                    "name": "web-app",
                    "image": "alpha5/web-app",
                    "context": "web",
                    "dockerfile": "Dockerfile",
                    "environment": "dev",
                    "auto_deploy": False,
                }
            ],
        },
    }


def load() -> dict:
    with LOCK:
        return _read()


def preview() -> dict:
    """Settings file for display before PostgreSQL is connected. Does not write."""
    with LOCK:
        return _seed_config()


def ensure_exported() -> dict | None:
    if not repo_ready():
        raise ConfigError("Run the console from the Kubernetes-Alpha5 repository to save settings.")
    if not database.can_connect():
        return None
    with LOCK:
        cfg = _read()
        _export(cfg)
        return cfg


def seed_and_store() -> dict:
    if not repo_ready():
        raise ConfigError("Run the console from the Kubernetes-Alpha5 repository to save settings.")
    with LOCK:
        cfg = _seed_config()
        _write_config(cfg)
        _export(cfg)
        return cfg


def save_proxmox(payload: dict) -> dict:
    return _update(lambda cfg: {**cfg, "proxmox": _proxmox(payload)})


def save_cluster(payload: dict) -> dict:
    return _update(lambda cfg: {**cfg, "cluster": _cluster(payload)})


def save_monitoring(payload: dict) -> dict:
    return _update(lambda cfg: {**cfg, "monitoring": {**_monitoring(payload), "checks": cfg["monitoring"]["checks"]}})


def add_host(payload: dict) -> dict:
    host = _host_record(payload)
    def apply(cfg: dict) -> dict:
        if any(item["name"] == host["name"] for item in cfg["hosts"]):
            raise ConfigError(f"Host {host['name']} already exists")
        return {**cfg, "hosts": [*cfg["hosts"], host]}
    return _update(apply)


def replace_host(name: str, payload: dict) -> dict:
    current = _name(name, "Host")
    host = _host_record({**payload, "name": current})
    def apply(cfg: dict) -> dict:
        if not any(item["name"] == current for item in cfg["hosts"]):
            raise ConfigError(f"Host {current} was not found")
        return {**cfg, "hosts": [host if item["name"] == current else item for item in cfg["hosts"]]}
    return _update(apply)


def delete_host(name: str) -> dict:
    current = _name(name, "Host")
    def apply(cfg: dict) -> dict:
        kept = [item for item in cfg["hosts"] if item["name"] != current]
        if len(kept) == len(cfg["hosts"]):
            raise ConfigError(f"Host {current} was not found")
        return {**cfg, "hosts": kept}
    return _update(apply)


def add_software(payload: dict) -> dict:
    item = _software(payload)
    def apply(cfg: dict) -> dict:
        if any(row["name"] == item["name"] for row in cfg["software"]):
            raise ConfigError(f"Package {item['name']} already exists")
        return {**cfg, "software": [*cfg["software"], item]}
    return _update(apply)


def replace_software(name: str, payload: dict) -> dict:
    current = _package_name(name)
    item = _software({**payload, "name": current})
    def apply(cfg: dict) -> dict:
        if not any(row["name"] == current for row in cfg["software"]):
            raise ConfigError(f"Package {current} was not found")
        return {**cfg, "software": [item if row["name"] == current else row for row in cfg["software"]]}
    return _update(apply)


def delete_software(name: str) -> dict:
    current = _package_name(name)
    return _delete_named("software", current, "Package")


def add_update(payload: dict) -> dict:
    item = _update_record(payload)
    def apply(cfg: dict) -> dict:
        if any(row["name"] == item["name"] for row in cfg["updates"]):
            raise ConfigError(f"Schedule {item['name']} already exists")
        return {**cfg, "updates": [*cfg["updates"], item]}
    return _update(apply)


def replace_update(name: str, payload: dict) -> dict:
    current = _name(name, "Schedule")
    item = _update_record({**payload, "name": current})
    def apply(cfg: dict) -> dict:
        if not any(row["name"] == current for row in cfg["updates"]):
            raise ConfigError(f"Schedule {current} was not found")
        return {**cfg, "updates": [item if row["name"] == current else row for row in cfg["updates"]]}
    return _update(apply)


def delete_update(name: str) -> dict:
    return _delete_named("updates", _name(name, "Schedule"), "Schedule")


def add_check(payload: dict) -> dict:
    item = _check(payload)
    def apply(cfg: dict) -> dict:
        checks = cfg["monitoring"]["checks"]
        if any(row["name"] == item["name"] for row in checks):
            raise ConfigError(f"Check {item['name']} already exists")
        monitoring = {**cfg["monitoring"], "checks": [*checks, item]}
        return {**cfg, "monitoring": monitoring}
    return _update(apply)


def delete_check(name: str) -> dict:
    current = _name(name, "Check")
    def apply(cfg: dict) -> dict:
        checks = [row for row in cfg["monitoring"]["checks"] if row["name"] != current]
        if len(checks) == len(cfg["monitoring"]["checks"]):
            raise ConfigError(f"Check {current} was not found")
        return {**cfg, "monitoring": {**cfg["monitoring"], "checks": checks}}
    return _update(apply)


def add_service(payload: dict) -> dict:
    environment = _environment(payload.get("environment", ""))
    service = _service_record(payload)
    def apply(cfg: dict) -> dict:
        current = cfg["services"][environment]
        if any(row["name"] == service["name"] for row in current):
            raise ConfigError(f"Service {service['name']} already exists in {environment}")
        services = {**cfg["services"], environment: [*current, service]}
        return {**cfg, "services": services}
    return _update(apply)


def replace_service(environment: str, name: str, payload: dict) -> dict:
    env = _environment(environment)
    current_name = _name(name, "Service")
    service = _service_record({**payload, "name": current_name})
    def apply(cfg: dict) -> dict:
        rows = cfg["services"][env]
        if not any(row["name"] == current_name for row in rows):
            raise ConfigError(f"Service {current_name} was not found in {env}")
        services = {**cfg["services"], env: [service if row["name"] == current_name else row for row in rows]}
        return {**cfg, "services": services}
    return _update(apply)


def delete_service(environment: str, name: str) -> dict:
    env = _environment(environment)
    current_name = _name(name, "Service")
    def apply(cfg: dict) -> dict:
        rows = [row for row in cfg["services"][env] if row["name"] != current_name]
        if len(rows) == len(cfg["services"][env]):
            raise ConfigError(f"Service {current_name} was not found in {env}")
        return {**cfg, "services": {**cfg["services"], env: rows}}
    return _update(apply)


def save_cicd(payload: dict) -> dict:
    def apply(cfg: dict) -> dict:
        cicd = _cicd(payload, cfg["cicd"]["pipelines"])
        return {**cfg, "cicd": cicd}
    return _update(apply)


def add_pipeline(payload: dict) -> dict:
    item = _pipeline(payload)
    def apply(cfg: dict) -> dict:
        if any(row["name"] == item["name"] for row in cfg["cicd"]["pipelines"]):
            raise ConfigError(f"Pipeline {item['name']} already exists")
        cicd = {**cfg["cicd"], "pipelines": [*cfg["cicd"]["pipelines"], item]}
        return {**cfg, "cicd": cicd}
    return _update(apply)


def replace_pipeline(name: str, payload: dict) -> dict:
    current = _name(name, "Pipeline")
    item = _pipeline({**payload, "name": current})
    def apply(cfg: dict) -> dict:
        rows = cfg["cicd"]["pipelines"]
        if not any(row["name"] == current for row in rows):
            raise ConfigError(f"Pipeline {current} was not found")
        cicd = {**cfg["cicd"], "pipelines": [item if row["name"] == current else row for row in rows]}
        return {**cfg, "cicd": cicd}
    return _update(apply)


def delete_pipeline(name: str) -> dict:
    current = _name(name, "Pipeline")
    def apply(cfg: dict) -> dict:
        rows = [row for row in cfg["cicd"]["pipelines"] if row["name"] != current]
        if len(rows) == len(cfg["cicd"]["pipelines"]):
            raise ConfigError(f"Pipeline {current} was not found")
        return {**cfg, "cicd": {**cfg["cicd"], "pipelines": rows}}
    return _update(apply)


def http_checks(cfg: dict) -> list[dict]:
    checks = []
    for environment, services in cfg["services"].items():
        for service in services:
            if service["monitor"] and service["enable_ingress"] and service["ingress_host"]:
                checks.append({
                    "name": f"{environment}-{service['name']}",
                    "environment": environment,
                    "url": f"https://{service['ingress_host']}/health",
                    "source": "service",
                })
    for check in cfg["monitoring"]["checks"]:
        checks.append({**check, "environment": "", "source": "manual"})
    return checks


def scrape_jobs(cfg: dict) -> list[dict]:
    targets = [f"{host['address']}:9100" for host in cfg["hosts"] if host["monitor"]]
    if not targets:
        return []
    return [{"job_name": "alpha5-nodes", "metrics_path": "/metrics", "targets": targets}]


def _update(mutator) -> dict:
    if not repo_ready():
        raise ConfigError("Run the console from the Kubernetes-Alpha5 repository to save settings.")
    with LOCK:
        try:
            cfg = mutator(_read())
            cfg = _validate(cfg)
            _write_config(cfg)
            _export(cfg)
        except database.DatabaseError as exc:
            raise ConfigError(str(exc)) from exc
        return cfg


def _delete_named(section: str, name: str, label: str) -> dict:
    def apply(cfg: dict) -> dict:
        kept = [item for item in cfg[section] if item["name"] != name]
        if len(kept) == len(cfg[section]):
            raise ConfigError(f"{label} {name} was not found")
        return {**cfg, section: kept}
    return _update(apply)


def _read() -> dict:
    try:
        stored = database.load_config()
    except database.DatabaseError as exc:
        raise ConfigError(str(exc)) from exc
    if stored is None:
        cfg = _seed_config()
        try:
            database.save_config(cfg)
        except database.DatabaseError as exc:
            raise ConfigError(str(exc)) from exc
        _write_text(CONFIG_PATH, json.dumps(cfg, indent=2) + "\n")
        return cfg
    return _validate(stored)


def _seed_config() -> dict:
    if CONFIG_PATH.is_file():
        try:
            return _validate(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, ConfigError):
            pass
    return _validate(default_config())


def _write_config(cfg: dict) -> None:
    try:
        database.save_config(cfg)
    except database.DatabaseError as exc:
        raise ConfigError(str(exc)) from exc
    _write_text(CONFIG_PATH, json.dumps(cfg, indent=2) + "\n")


def _export(cfg: dict) -> None:
    _write_text(REPO / "ansible" / "inventory.yml", _inventory(cfg))
    _write_text(REPO / "ansible" / "group_vars" / "platform.yml", _group_vars(cfg))
    _write_text(REPO / "monitoring" / "http-checks.yml", _http_checks_yaml(cfg))
    _write_text(REPO / ".github" / "workflows" / "deploy.yml", _workflow(cfg))
    jobs = scrape_jobs(cfg)
    for environment in ENVIRONMENTS:
        enabled = environment in cfg["monitoring"]["environments"]
        payload = {
            "app_configs": {service["name"]: _service_tf(service) for service in cfg["services"][environment]},
            "enable_monitoring": enabled,
            "enable_grafana": enabled and cfg["monitoring"]["grafana"],
            "enable_grafana_ingress": enabled and cfg["monitoring"]["grafana_ingress"],
            "grafana_ingress_host": cfg["monitoring"]["grafana_host"],
            "monitoring_scrape_jobs": jobs if enabled else [],
        }
        _write_text(
            REPO / "environments" / environment / "platform.auto.tfvars.json",
            json.dumps(payload, indent=2) + "\n",
        )


def _inventory(cfg: dict) -> str:
    cluster = cfg["cluster"]
    lines = [
        "# Generated by the Alpha5 console. Edit hosts from the web console.",
        "all:",
        "  vars:",
        f"    ansible_user: {_yaml(cluster['ansible_user'])}",
        f"    ansible_ssh_private_key_file: {_yaml(cluster['ssh_private_key_file'])}",
        "    ansible_python_interpreter: /usr/bin/python3",
        f"    kubernetes_version: {_yaml(cluster['kubernetes_version'])}",
        f"    container_runtime: {_yaml(cluster['container_runtime'])}",
        f"    pod_network_cidr: {_yaml(cluster['pod_network_cidr'])}",
        f"    service_cidr: {_yaml(cluster['service_cidr'])}",
        f"    install_method: {_yaml(cluster['install_method'])}",
        f"    cni_plugin: {_yaml(cluster['cni_plugin'])}",
        f"    cluster_name: {_yaml(cluster['name'])}",
        "  children:",
        "    k8s_nodes:",
        "      children:",
        "        control_plane:",
        "          hosts:",
    ]
    lines.extend(_inventory_hosts(cfg, "control_plane"))
    lines.extend([
        "          vars:",
        "            is_control_plane: true",
        "        workers:",
        "          hosts:",
    ])
    lines.extend(_inventory_hosts(cfg, "worker"))
    lines.extend([
        "          vars:",
        "            is_control_plane: false",
        "    local:",
        "      hosts:",
        "        localhost:",
        "          ansible_connection: local",
        "",
    ])
    return "\n".join(lines)


def _inventory_hosts(cfg: dict, role: str) -> list[str]:
    hosts = [host for host in cfg["hosts"] if host["role"] == role]
    if not hosts:
        return ["            {}"]
    lines = []
    for host in hosts:
        lines.append(f"            {host['name']}:")
        lines.append(f"              ansible_host: {_yaml(host['address'])}")
        lines.append(f"              node_name: {_yaml(host['node_name'])}")
        lines.append(f"              proxmox_node: {_yaml(host['proxmox_node'])}")
        if host["vmid"] is not None:
            lines.append(f"              vmid: {host['vmid']}")
        lines.append(f"              cores: {host['cores']}")
        lines.append(f"              memory_mb: {host['memory_mb']}")
        lines.append(f"              disk_gb: {host['disk_gb']}")
        lines.append(f"              monitor: {_yaml(host['monitor'])}")
    return lines


def _group_vars(cfg: dict) -> str:
    proxmox = cfg["proxmox"]
    cluster = cfg["cluster"]
    lines = [
        "# Generated by the Alpha5 console. Edit these values from the web console.",
        "platform_generated: true",
        f"proxmox_api_host: {_yaml(proxmox['api_host'])}",
        f"proxmox_api_user: {_yaml(proxmox['api_user'])}",
        f"proxmox_token_id: {_yaml(proxmox['token_id'])}",
        f"proxmox_node: {_yaml(proxmox['node'])}",
        f"proxmox_storage: {_yaml(proxmox['storage'])}",
        f"proxmox_bridge: {_yaml(proxmox['bridge'])}",
        f"proxmox_template: {_yaml(proxmox['template'])}",
        f"proxmox_cidr_prefix: {proxmox['cidr_prefix']}",
        f"proxmox_gateway: {_yaml(proxmox['gateway'])}",
        f"proxmox_nameserver: {_yaml(proxmox['nameserver'])}",
        f"kubernetes_version: {_yaml(cluster['kubernetes_version'])}",
        f"container_runtime: {_yaml(cluster['container_runtime'])}",
        f"pod_network_cidr: {_yaml(cluster['pod_network_cidr'])}",
        f"service_cidr: {_yaml(cluster['service_cidr'])}",
        f"install_method: {_yaml(cluster['install_method'])}",
        f"cni_plugin: {_yaml(cluster['cni_plugin'])}",
        f"cluster_name: {_yaml(cluster['name'])}",
        "platform_hosts:",
    ]
    if not cfg["hosts"]:
        lines.append("  []")
    for host in cfg["hosts"]:
        lines.append(f"  - name: {_yaml(host['name'])}")
        lines.append(f"    address: {_yaml(host['address'])}")
        lines.append(f"    role: {_yaml(host['role'])}")
        lines.append(f"    node_name: {_yaml(host['node_name'])}")
        lines.append(f"    proxmox_node: {_yaml(host['proxmox_node'])}")
        if host["vmid"] is not None:
            lines.append(f"    vmid: {host['vmid']}")
        lines.append(f"    cores: {host['cores']}")
        lines.append(f"    memory_mb: {host['memory_mb']}")
        lines.append(f"    disk_gb: {host['disk_gb']}")
        lines.append(f"    monitor: {_yaml(host['monitor'])}")
    lines.append("platform_software:")
    if not cfg["software"]:
        lines.append("  []")
    for item in cfg["software"]:
        lines.append(f"  - name: {_yaml(item['name'])}")
        lines.append(f"    version: {_yaml(item['version'])}")
        lines.append(f"    scope: {_yaml(item['scope'])}")
    lines.append("platform_updates:")
    if not cfg["updates"]:
        lines.append("  []")
    for item in cfg["updates"]:
        lines.append(f"  - name: {_yaml(item['name'])}")
        lines.append(f"    cron: {_yaml(item['cron'])}")
        lines.append(f"    scope: {_yaml(item['scope'])}")
        lines.append(f"    action: {_yaml(item['action'])}")
        lines.append(f"    job: {_yaml(ACTIONS[item['action']])}")
        lines.append(f"    enabled: {_yaml(item['enabled'])}")
    lines.append("")
    return "\n".join(lines)


def _http_checks_yaml(cfg: dict) -> str:
    lines = ["# Generated by the Alpha5 console.", "checks:"]
    checks = http_checks(cfg)
    if not checks:
        lines.append("  []")
    for check in checks:
        lines.append(f"  - name: {_yaml(check['name'])}")
        lines.append(f"    url: {_yaml(check['url'])}")
        lines.append(f"    source: {_yaml(check['source'])}")
    lines.append("")
    return "\n".join(lines)


def _workflow(cfg: dict) -> str:
    cicd = cfg["cicd"]
    lines = [
        "# Generated by the Alpha5 console. Edit pipelines from the web console.",
        "name: Build and deploy",
        "on:",
        "  push:",
        "    branches:",
    ]
    branches = list(dict.fromkeys(cicd["branches"].values()))
    for branch in branches:
        lines.append(f"      - {_yaml(branch)}")
    lines.extend([
        "  workflow_dispatch:",
        "permissions:",
        "  contents: read",
        "  packages: write",
        "concurrency:",
        "  group: deploy-${{ github.ref }}",
        "  cancel-in-progress: false",
        "jobs:",
        "  validate:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - uses: actions/checkout@v4",
        "      - uses: hashicorp/setup-terraform@v3",
        "      - run: terraform -chdir=terraform init -backend=false",
        "      - run: terraform -chdir=terraform validate",
    ])
    for pipeline in cicd["pipelines"]:
        branch = cicd["branches"][pipeline["environment"]]
        job = pipeline["name"]
        image = f"{cicd['registry']}/{pipeline['image']}"
        lines.extend([
            f"  build-{job}:",
            "    runs-on: ubuntu-latest",
            "    needs: validate",
            f"    if: github.ref == 'refs/heads/{branch}'",
            "    steps:",
            "      - uses: actions/checkout@v4",
            "      - uses: docker/setup-buildx-action@v3",
            "      - uses: docker/login-action@v3",
            "        with:",
            f"          registry: {cicd['registry']}",
            "          username: ${{ github.actor }}",
            "          password: ${{ secrets.GITHUB_TOKEN }}",
            "      - uses: docker/build-push-action@v6",
            "        with:",
            f"          context: {pipeline['context']}",
            f"          file: {pipeline['context']}/{pipeline['dockerfile']}",
            "          push: true",
            f"          tags: {image}:${{{{ github.sha }}}}",
        ])
        if pipeline["auto_deploy"]:
            lines.extend([
                f"  deploy-{job}:",
                "    runs-on: ubuntu-latest",
                f"    needs: build-{job}",
                f"    if: github.ref == 'refs/heads/{branch}'",
                f"    environment: {pipeline['environment']}",
                "    steps:",
                "      - uses: actions/checkout@v4",
                "      - uses: hashicorp/setup-terraform@v3",
                "      - name: Write kubeconfig",
                "        run: printf '%s' \"$KUBE_CONFIG_DATA\" > \"$RUNNER_TEMP/kubeconfig\"",
                "        env:",
                "          KUBE_CONFIG_DATA: ${{ secrets.KUBE_CONFIG }}",
                f"      - run: terraform -chdir=terraform init",
                f"      - run: terraform -chdir=terraform apply -auto-approve -var-file=../environments/{pipeline['environment']}/terraform.tfvars",
                "        env:",
                "          KUBECONFIG: ${{ runner.temp }}/kubeconfig",
            ])
    lines.append("")
    return "\n".join(lines)


def _service_tf(service: dict) -> dict:
    return {
        "image": service["image"],
        "image_tag": service["image_tag"],
        "replicas": service["replicas"],
        "cpu_request": service["cpu_request"],
        "memory_request": service["memory_request"],
        "cpu_limit": service["cpu_limit"],
        "memory_limit": service["memory_limit"],
        "port": service["port"],
        "env_vars": {item["key"]: item["value"] for item in service["env"]},
        "enable_ingress": service["enable_ingress"],
        "ingress_host": service["ingress_host"],
        "enable_service": service["enable_service"],
        "service_type": service["service_type"],
    }


def _validate(cfg: dict) -> dict:
    if not isinstance(cfg, dict):
        raise ConfigError("Configuration must be an object")
    services = cfg.get("services", {})
    if not isinstance(services, dict):
        raise ConfigError("Services must be an object")
    return {
        "proxmox": _proxmox(cfg.get("proxmox", {})),
        "cluster": _cluster(cfg.get("cluster", {})),
        "hosts": _unique([_host_record(item) for item in _list(cfg.get("hosts"), "Hosts")], "Host"),
        "software": _unique([_software(item) for item in _list(cfg.get("software"), "Software")], "Package"),
        "updates": _unique([_update_record(item) for item in _list(cfg.get("updates"), "Updates")], "Schedule"),
        "monitoring": _monitoring(cfg.get("monitoring", {})),
        "services": {
            env: _unique([_service_record(item) for item in _list(services.get(env, []), env)], "Service")
            for env in ENVIRONMENTS
        },
        "cicd": _cicd(cfg.get("cicd", {}), (cfg.get("cicd") or {}).get("pipelines", [])),
    }


def _proxmox(payload: dict) -> dict:
    data = _object(payload, "Proxmox")
    api_host = _clean_host(str(data.get("api_host", "")), allow_empty=True)
    return {
        "api_host": api_host,
        "api_user": _bounded(data.get("api_user", "root@pam"), "Proxmox user", 64),
        "token_id": _bounded(data.get("token_id", ""), "Token id", 128, allow_empty=True),
        "node": _match(NAME, data.get("node", "pve"), "Proxmox node"),
        "storage": _bounded(data.get("storage", "local-lvm"), "Storage", 64),
        "bridge": _bounded(data.get("bridge", "vmbr0"), "Bridge", 32),
        "template": _bounded(data.get("template", "ubuntu-2204"), "Template", 64),
        "cidr_prefix": _integer(data.get("cidr_prefix", 24), "CIDR prefix", 8, 30),
        "gateway": _ipv4(data.get("gateway", ""), "Gateway", allow_empty=True),
        "nameserver": _ipv4(data.get("nameserver", "1.1.1.1"), "Nameserver"),
    }


def _cluster(payload: dict) -> dict:
    data = _object(payload, "Cluster")
    method = str(data.get("install_method", "kubeadm"))
    runtime = str(data.get("container_runtime", "containerd"))
    cni = str(data.get("cni_plugin", "flannel"))
    if method not in INSTALL_METHODS:
        raise ConfigError("Install method must be kubeadm, k3s, or rke2")
    if runtime not in RUNTIMES:
        raise ConfigError("Container runtime must be containerd or docker")
    if cni not in CNIS:
        raise ConfigError("CNI plugin must be flannel, calico, or weave")
    key = str(data.get("ssh_private_key_file", "~/.ssh/id_rsa")).strip()
    if not KEY_PATH.fullmatch(key) or ".." in key:
        raise ConfigError("SSH key path is not valid")
    return {
        "name": _match(NAME, data.get("name", "alpha5"), "Cluster name"),
        "install_method": method,
        "kubernetes_version": _match(TAG, data.get("kubernetes_version", "1.34.0"), "Kubernetes version"),
        "container_runtime": runtime,
        "cni_plugin": cni,
        "pod_network_cidr": _cidr(data.get("pod_network_cidr", "")),
        "service_cidr": _cidr(data.get("service_cidr", "")),
        "ansible_user": _match(USER, data.get("ansible_user", "support"), "SSH user"),
        "ssh_private_key_file": key,
    }


def _host_record(payload: dict) -> dict:
    data = _object(payload, "Host")
    role = str(data.get("role", "worker"))
    if role not in ROLES:
        raise ConfigError("Host role must be control_plane or worker")
    vmid_raw = data.get("vmid", None)
    vmid = None if vmid_raw in (None, "", "null") else _integer(vmid_raw, "VM ID", 100, 999999999)
    proxmox_node = str(data.get("proxmox_node", "")).strip()
    if proxmox_node and not NAME.fullmatch(proxmox_node):
        raise ConfigError("Proxmox node name is not valid")
    return {
        "name": _match(NAME, data.get("name", ""), "Host name"),
        "address": _ipv4(data.get("address", ""), "Host address"),
        "role": role,
        "node_name": _match(NAME, data.get("node_name", data.get("name", "")), "Node name"),
        "proxmox_node": proxmox_node,
        "vmid": vmid,
        "cores": _integer(data.get("cores", 4), "Cores", 1, 64),
        "memory_mb": _integer(data.get("memory_mb", 8192), "Memory", 1024, 262144),
        "disk_gb": _integer(data.get("disk_gb", 80), "Disk", 16, 4000),
        "monitor": _bool(data.get("monitor", True)),
    }


def _software(payload: dict) -> dict:
    data = _object(payload, "Software")
    scope = str(data.get("scope", "all"))
    if scope not in SCOPES:
        raise ConfigError("Software scope must be all, control_plane, or workers")
    version = str(data.get("version", "latest")).strip()
    if version != "latest" and not TAG.fullmatch(version):
        raise ConfigError("Package version is not valid")
    return {
        "name": _package_name(data.get("name", "")),
        "version": version,
        "scope": scope,
    }


def _update_record(payload: dict) -> dict:
    data = _object(payload, "Update")
    scope = str(data.get("scope", "all"))
    action = str(data.get("action", "unattended-upgrades"))
    if scope not in SCOPES:
        raise ConfigError("Update scope must be all, control_plane, or workers")
    if action not in ACTIONS:
        raise ConfigError("Update action must be unattended-upgrades or apt-upgrade")
    cron = str(data.get("cron", "")).strip()
    fields = cron.split()
    if len(fields) != 5 or any(not CRON_FIELD.fullmatch(field) for field in fields):
        raise ConfigError("Cron schedule must be five fields, such as 0 3 * * 0")
    return {
        "name": _name(data.get("name", ""), "Schedule"),
        "cron": cron,
        "scope": scope,
        "action": action,
        "enabled": _bool(data.get("enabled", True)),
    }


def _monitoring(payload: dict) -> dict:
    data = _object(payload, "Monitoring")
    environments = data.get("environments", ["dev"])
    if not isinstance(environments, list) or not environments:
        raise ConfigError("Choose at least one monitoring environment")
    cleaned = []
    for environment in environments:
        env = _environment(environment)
        if env not in cleaned:
            cleaned.append(env)
    checks = data.get("checks", [])
    return {
        "environments": cleaned,
        "grafana": _bool(data.get("grafana", True)),
        "grafana_ingress": _bool(data.get("grafana_ingress", True)),
        "grafana_host": _match(HOST, data.get("grafana_host", "grafana.alpha5.finance"), "Grafana host"),
        "checks": _unique([_check(item) for item in _list(checks, "Checks")], "Check"),
    }


def _check(payload: dict) -> dict:
    data = _object(payload, "Check")
    url = str(data.get("url", "")).strip()
    if not URL.fullmatch(url):
        raise ConfigError("Check URL must start with http:// or https://")
    return {"name": _name(data.get("name", ""), "Check"), "url": url}


def _service_record(payload: dict) -> dict:
    data = _object(payload, "Service")
    service_type = str(data.get("service_type", "ClusterIP"))
    if service_type not in SERVICE_TYPES:
        raise ConfigError("Service type must be ClusterIP, NodePort, or LoadBalancer")
    enable_ingress = _bool(data.get("enable_ingress", True))
    ingress_host = str(data.get("ingress_host", "")).strip()
    if enable_ingress:
        ingress_host = _match(HOST, ingress_host, "Ingress host")
    elif ingress_host and not HOST.fullmatch(ingress_host):
        raise ConfigError("Ingress host is not valid")
    env = data.get("env", [])
    if isinstance(env, dict):
        env = [{"key": key, "value": value} for key, value in env.items()]
    return {
        "name": _name(data.get("name", ""), "Service"),
        "image": _match(IMAGE, data.get("image", ""), "Image"),
        "image_tag": _match(TAG, data.get("image_tag", "latest"), "Image tag"),
        "replicas": _integer(data.get("replicas", 1), "Replicas", 1, 30),
        "cpu_request": _match(CPU, data.get("cpu_request", "100m"), "CPU request"),
        "memory_request": _match(MEMORY, data.get("memory_request", "128Mi"), "Memory request"),
        "cpu_limit": _match(CPU, data.get("cpu_limit", "500m"), "CPU limit"),
        "memory_limit": _match(MEMORY, data.get("memory_limit", "512Mi"), "Memory limit"),
        "port": _integer(data.get("port", 8080), "Port", 1, 65535),
        "env": [_env_pair(item) for item in _list(env, "Environment variables")],
        "enable_ingress": enable_ingress,
        "ingress_host": ingress_host,
        "enable_service": _bool(data.get("enable_service", True)),
        "service_type": service_type,
        "monitor": _bool(data.get("monitor", True)),
    }


def _cicd(payload: dict, pipelines) -> dict:
    data = _object(payload, "CI/CD")
    branches_in = data.get("branches", {})
    if not isinstance(branches_in, dict):
        raise ConfigError("Branches must be an object")
    branches = {}
    for environment in ENVIRONMENTS:
        branches[environment] = _branch(branches_in.get(environment, environment))
    return {
        "registry": _match(REGISTRY, data.get("registry", "ghcr.io"), "Registry"),
        "branches": branches,
        "pipelines": _unique([_pipeline(item) for item in _list(pipelines, "Pipelines")], "Pipeline"),
    }


def _pipeline(payload: dict) -> dict:
    data = _object(payload, "Pipeline")
    environment = _environment(data.get("environment", "dev"))
    context = _rel_path(data.get("context", "."), "Build context")
    dockerfile = _rel_path(data.get("dockerfile", "Dockerfile"), "Dockerfile")
    if ".." in context or ".." in dockerfile:
        raise ConfigError("Build paths cannot contain ..")
    return {
        "name": _name(data.get("name", ""), "Pipeline"),
        "image": _match(IMAGE, data.get("image", ""), "Image"),
        "context": context,
        "dockerfile": dockerfile,
        "environment": environment,
        "auto_deploy": _bool(data.get("auto_deploy", False)),
    }


def _host(name: str, address: str, role: str, node_name: str) -> dict:
    return {
        "name": name,
        "address": address,
        "role": role,
        "node_name": node_name,
        "proxmox_node": "",
        "vmid": None,
        "cores": 4,
        "memory_mb": 8192,
        "disk_gb": 80,
        "monitor": True,
    }


def _service(name, image, tag, replicas, cpu_request, memory_request, cpu_limit, memory_limit, port, host, env) -> dict:
    return {
        "name": name,
        "image": image,
        "image_tag": tag,
        "replicas": replicas,
        "cpu_request": cpu_request,
        "memory_request": memory_request,
        "cpu_limit": cpu_limit,
        "memory_limit": memory_limit,
        "port": port,
        "env": [{"key": key, "value": value} for key, value in env],
        "enable_ingress": True,
        "ingress_host": host,
        "enable_service": True,
        "service_type": "ClusterIP",
        "monitor": True,
    }


def _env_pair(payload: dict) -> dict:
    data = _object(payload, "Environment variable")
    value = str(data.get("value", ""))
    if "\n" in value or len(value) > 512:
        raise ConfigError("Environment variable values must be a single line")
    return {"key": _match(ENV_KEY, data.get("key", ""), "Environment variable"), "value": value}


def _environment(value) -> str:
    value = str(value).strip()
    if value not in ENVIRONMENTS:
        raise ConfigError("Environment must be dev, staging, or prod")
    return value


def _branch(value) -> str:
    value = str(value).strip()
    if not BRANCH.fullmatch(value) or ".." in value:
        raise ConfigError("Branch name is not valid")
    return value


def _rel_path(value, label: str) -> str:
    value = str(value).strip().replace("\\", "/")
    if not REL_PATH.fullmatch(value):
        raise ConfigError(f"{label} must be a relative path")
    return value


def _name(value, label: str) -> str:
    return _match(NAME, value, label)


def _package_name(value) -> str:
    return _match(PACKAGE, value, "Package name")


def _match(pattern: re.Pattern, value, label: str) -> str:
    text = str(value).strip()
    if not pattern.fullmatch(text):
        raise ConfigError(f"{label} is not valid")
    return text


def _bounded(value, label: str, limit: int, allow_empty: bool = False) -> str:
    text = str(value).strip()
    if len(text) > limit or any(char in text for char in "\n\r\t"):
        raise ConfigError(f"{label} is not valid")
    if not text and not allow_empty:
        raise ConfigError(f"{label} is not valid")
    return text


def _ipv4(value, label: str, allow_empty: bool = False) -> str:
    text = str(value).strip()
    if allow_empty and text == "":
        return ""
    if not IPV4.fullmatch(text):
        raise ConfigError(f"{label} must be an IPv4 address")
    parts = [int(part) for part in text.split(".")]
    if any(part > 255 for part in parts):
        raise ConfigError(f"{label} must be an IPv4 address")
    return text


def _cidr(value) -> str:
    text = str(value).strip()
    if not CIDR.fullmatch(text):
        raise ConfigError("CIDR is not valid")
    address, prefix = text.split("/")
    _ipv4(address, "CIDR address")
    if not 1 <= int(prefix) <= 32:
        raise ConfigError("CIDR prefix must be between 1 and 32")
    return text


def _clean_host(value: str, allow_empty: bool) -> str:
    text = value.strip()
    text = re.sub(r"^https?://", "", text)
    text = text.split("/")[0]
    if ":" in text:
        text = text.split(":", 1)[0]
    if allow_empty and text == "":
        return ""
    return _match(HOST, text, "API host")


def _integer(value, label: str, low: int, high: int) -> int:
    if isinstance(value, bool) or value is None or str(value).strip() == "":
        raise ConfigError(f"{label} must be a whole number")
    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise ConfigError(f"{label} must be a whole number") from exc
    if not low <= number <= high:
        raise ConfigError(f"{label} must be between {low} and {high}")
    return number


def _bool(value) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _unique(items: list[dict], label: str) -> list[dict]:
    seen = set()
    for item in items:
        if item["name"] in seen:
            raise ConfigError(f"{label} {item['name']} is duplicated")
        seen.add(item["name"])
    return items


def _object(value, label: str) -> dict:
    if not isinstance(value, dict):
        raise ConfigError(f"{label} must be an object")
    return value


def _list(value, label: str) -> list:
    if not isinstance(value, list):
        raise ConfigError(f"{label} must be a list")
    return value


def _yaml(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    text = str(value)
    if (
        text == ""
        or re.fullmatch(r"\d+(?:\.\d+)+", text)
        or re.search(r"[:#{}[\],&*!|>'\"%@`\n\t]|(^\s)|(\s$)", text)
        or text.lower() in {"true", "false", "null", "yes", "no"}
    ):
        return json.dumps(text)
    return text


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    temporary.replace(path)
