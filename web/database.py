"""PostgreSQL storage for Alpha5 Deployment Center settings.

Connection details live in config/database.local.json, which is gitignored.
Passwords are never returned by the API.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import psycopg
from psycopg import sql
from psycopg.types.json import Json

REPO = Path(__file__).resolve().parent.parent
CONNECTION_PATH = REPO / "config" / "database.local.json"
HOST_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")

STATEMENTS = [
    """
    CREATE TABLE IF NOT EXISTS proxmox_settings (
        id SMALLINT PRIMARY KEY CHECK (id = 1),
        api_host TEXT NOT NULL,
        api_user TEXT NOT NULL,
        token_id TEXT NOT NULL,
        node TEXT NOT NULL,
        storage TEXT NOT NULL,
        bridge TEXT NOT NULL,
        template TEXT NOT NULL,
        cidr_prefix INTEGER NOT NULL,
        gateway TEXT NOT NULL,
        nameserver TEXT NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS cluster_settings (
        id SMALLINT PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        install_method TEXT NOT NULL,
        kubernetes_version TEXT NOT NULL,
        container_runtime TEXT NOT NULL,
        cni_plugin TEXT NOT NULL,
        pod_network_cidr TEXT NOT NULL,
        service_cidr TEXT NOT NULL,
        ansible_user TEXT NOT NULL,
        ssh_private_key_file TEXT NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS hosts (
        name TEXT PRIMARY KEY,
        address TEXT NOT NULL,
        role TEXT NOT NULL,
        node_name TEXT NOT NULL,
        proxmox_node TEXT NOT NULL,
        vmid INTEGER,
        cores INTEGER NOT NULL,
        memory_mb INTEGER NOT NULL,
        disk_gb INTEGER NOT NULL,
        monitor BOOLEAN NOT NULL,
        position INTEGER NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS software_packages (
        name TEXT PRIMARY KEY,
        version TEXT NOT NULL,
        scope TEXT NOT NULL,
        position INTEGER NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS update_schedules (
        name TEXT PRIMARY KEY,
        cron TEXT NOT NULL,
        scope TEXT NOT NULL,
        action TEXT NOT NULL,
        enabled BOOLEAN NOT NULL,
        position INTEGER NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS monitoring_settings (
        id SMALLINT PRIMARY KEY CHECK (id = 1),
        environments JSONB NOT NULL,
        grafana BOOLEAN NOT NULL,
        grafana_ingress BOOLEAN NOT NULL,
        grafana_host TEXT NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS health_checks (
        name TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        position INTEGER NOT NULL
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS services (
        environment TEXT NOT NULL,
        name TEXT NOT NULL,
        image TEXT NOT NULL,
        image_tag TEXT NOT NULL,
        replicas INTEGER NOT NULL,
        cpu_request TEXT NOT NULL,
        memory_request TEXT NOT NULL,
        cpu_limit TEXT NOT NULL,
        memory_limit TEXT NOT NULL,
        port INTEGER NOT NULL,
        enable_ingress BOOLEAN NOT NULL,
        ingress_host TEXT NOT NULL,
        enable_service BOOLEAN NOT NULL,
        service_type TEXT NOT NULL,
        monitor BOOLEAN NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (environment, name)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS service_variables (
        environment TEXT NOT NULL,
        service_name TEXT NOT NULL,
        env_key TEXT NOT NULL,
        env_value TEXT NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (environment, service_name, env_key),
        FOREIGN KEY (environment, service_name)
            REFERENCES services (environment, name) ON DELETE CASCADE
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS cicd_settings (
        id SMALLINT PRIMARY KEY CHECK (id = 1),
        registry TEXT NOT NULL,
        branch_dev TEXT NOT NULL,
        branch_staging TEXT NOT NULL,
        branch_prod TEXT NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS pipelines (
        name TEXT PRIMARY KEY,
        image TEXT NOT NULL,
        context TEXT NOT NULL,
        dockerfile TEXT NOT NULL,
        environment TEXT NOT NULL,
        auto_deploy BOOLEAN NOT NULL,
        position INTEGER NOT NULL
    )
    """,
]


class DatabaseError(RuntimeError):
    """The PostgreSQL connection or save failed."""


def status() -> dict:
    saved = _read_local()
    result = _public_connection(saved)
    if saved is None:
        result["error"] = "No PostgreSQL connection has been saved."
        return result
    try:
        with _connect(saved) as conn:
            row = conn.execute("SHOW server_version").fetchone()
        result["connected"] = True
        result["version"] = row[0] if row else ""
    except (psycopg.Error, OSError) as exc:
        result["error"] = _public_error(exc, saved.get("password", ""))
    return result


def can_connect() -> bool:
    return bool(status()["connected"])


def save_connection(payload: dict) -> dict:
    current = _read_local()
    settings = _validate_connection(payload, current)
    try:
        _prepare_database(settings)
    except psycopg.Error as exc:
        raise DatabaseError(_public_error(exc, settings["password"])) from exc
    _write_local(settings)
    return status()


def load_config() -> dict | None:
    settings = _read_local()
    if settings is None:
        raise DatabaseError("Save a PostgreSQL connection on the Database screen first.")
    try:
        with _connect(settings) as conn:
            if conn.execute("SELECT 1 FROM proxmox_settings WHERE id = 1").fetchone() is None:
                return None
            return _read_rows(conn)
    except psycopg.Error as exc:
        raise DatabaseError(_public_error(exc, settings.get("password", ""))) from exc


def save_config(cfg: dict) -> None:
    settings = _read_local()
    if settings is None:
        raise DatabaseError("Save a PostgreSQL connection on the Database screen first.")
    try:
        with _connect(settings) as conn:
            with conn.transaction():
                _write_rows(conn, cfg)
    except psycopg.Error as exc:
        raise DatabaseError(_public_error(exc, settings.get("password", ""))) from exc


def _prepare_database(settings: dict) -> None:
    try:
        with _connect(settings) as conn:
            conn.execute("SELECT 1")
    except psycopg.OperationalError as exc:
        if "does not exist" not in str(exc).lower():
            raise
        _create_database(settings)
        with _connect(settings) as conn:
            conn.execute("SELECT 1")
    with _connect(settings) as conn:
        with conn.transaction():
            for statement in STATEMENTS:
                conn.execute(statement)


def _create_database(settings: dict) -> None:
    last_error: Exception | None = None
    for maintenance in ("postgres", "template1"):
        attempt = {**settings, "database": maintenance}
        try:
            with psycopg.connect(_dsn(attempt), autocommit=True, connect_timeout=10) as conn:
                conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(settings["database"])))
            return
        except psycopg.errors.DuplicateDatabase:
            return
        except psycopg.Error as exc:
            last_error = exc
    if last_error is not None:
        raise last_error
    raise DatabaseError("Could not create the PostgreSQL database.")


def _read_rows(conn: psycopg.Connection) -> dict:
    proxmox = conn.execute(
        """
        SELECT api_host, api_user, token_id, node, storage, bridge, template,
               cidr_prefix, gateway, nameserver
        FROM proxmox_settings WHERE id = 1
        """
    ).fetchone()
    cluster = conn.execute(
        """
        SELECT name, install_method, kubernetes_version, container_runtime, cni_plugin,
               pod_network_cidr, service_cidr, ansible_user, ssh_private_key_file
        FROM cluster_settings WHERE id = 1
        """
    ).fetchone()
    monitoring = conn.execute(
        """
        SELECT environments, grafana, grafana_ingress, grafana_host
        FROM monitoring_settings WHERE id = 1
        """
    ).fetchone()
    cicd = conn.execute(
        "SELECT registry, branch_dev, branch_staging, branch_prod FROM cicd_settings WHERE id = 1"
    ).fetchone()
    if not all((proxmox, cluster, monitoring, cicd)):
        return None
    hosts = conn.execute(
        """
        SELECT name, address, role, node_name, proxmox_node, vmid, cores, memory_mb, disk_gb, monitor
        FROM hosts ORDER BY position, name
        """
    ).fetchall()
    software = conn.execute(
        "SELECT name, version, scope FROM software_packages ORDER BY position, name"
    ).fetchall()
    updates = conn.execute(
        "SELECT name, cron, scope, action, enabled FROM update_schedules ORDER BY position, name"
    ).fetchall()
    checks = conn.execute("SELECT name, url FROM health_checks ORDER BY position, name").fetchall()
    services = conn.execute(
        """
        SELECT environment, name, image, image_tag, replicas, cpu_request, memory_request,
               cpu_limit, memory_limit, port, enable_ingress, ingress_host, enable_service,
               service_type, monitor
        FROM services ORDER BY environment, position, name
        """
    ).fetchall()
    variables = conn.execute(
        """
        SELECT environment, service_name, env_key, env_value
        FROM service_variables ORDER BY environment, service_name, position, env_key
        """
    ).fetchall()
    pipelines = conn.execute(
        """
        SELECT name, image, context, dockerfile, environment, auto_deploy
        FROM pipelines ORDER BY position, name
        """
    ).fetchall()
    env_map: dict[tuple[str, str], list[dict]] = {}
    for environment, service_name, key, value in variables:
        env_map.setdefault((environment, service_name), []).append({"key": key, "value": value})
    grouped = {"dev": [], "staging": [], "prod": []}
    for row in services:
        environment = row[0]
        grouped.setdefault(environment, []).append({
            "name": row[1],
            "image": row[2],
            "image_tag": row[3],
            "replicas": row[4],
            "cpu_request": row[5],
            "memory_request": row[6],
            "cpu_limit": row[7],
            "memory_limit": row[8],
            "port": row[9],
            "enable_ingress": row[10],
            "ingress_host": row[11],
            "enable_service": row[12],
            "service_type": row[13],
            "monitor": row[14],
            "env": env_map.get((environment, row[1]), []),
        })
    return {
        "proxmox": {
            "api_host": proxmox[0],
            "api_user": proxmox[1],
            "token_id": proxmox[2],
            "node": proxmox[3],
            "storage": proxmox[4],
            "bridge": proxmox[5],
            "template": proxmox[6],
            "cidr_prefix": proxmox[7],
            "gateway": proxmox[8],
            "nameserver": proxmox[9],
        },
        "cluster": {
            "name": cluster[0],
            "install_method": cluster[1],
            "kubernetes_version": cluster[2],
            "container_runtime": cluster[3],
            "cni_plugin": cluster[4],
            "pod_network_cidr": cluster[5],
            "service_cidr": cluster[6],
            "ansible_user": cluster[7],
            "ssh_private_key_file": cluster[8],
        },
        "hosts": [
            {
                "name": row[0],
                "address": row[1],
                "role": row[2],
                "node_name": row[3],
                "proxmox_node": row[4],
                "vmid": row[5],
                "cores": row[6],
                "memory_mb": row[7],
                "disk_gb": row[8],
                "monitor": row[9],
            }
            for row in hosts
        ],
        "software": [{"name": row[0], "version": row[1], "scope": row[2]} for row in software],
        "updates": [
            {"name": row[0], "cron": row[1], "scope": row[2], "action": row[3], "enabled": row[4]}
            for row in updates
        ],
        "monitoring": {
            "environments": list(monitoring[0]),
            "grafana": monitoring[1],
            "grafana_ingress": monitoring[2],
            "grafana_host": monitoring[3],
            "checks": [{"name": row[0], "url": row[1]} for row in checks],
        },
        "services": grouped,
        "cicd": {
            "registry": cicd[0],
            "branches": {"dev": cicd[1], "staging": cicd[2], "prod": cicd[3]},
            "pipelines": [
                {
                    "name": row[0],
                    "image": row[1],
                    "context": row[2],
                    "dockerfile": row[3],
                    "environment": row[4],
                    "auto_deploy": row[5],
                }
                for row in pipelines
            ],
        },
    }


def _write_rows(conn: psycopg.Connection, cfg: dict) -> None:
    proxmox = cfg["proxmox"]
    conn.execute(
        """
        INSERT INTO proxmox_settings (
            id, api_host, api_user, token_id, node, storage, bridge, template,
            cidr_prefix, gateway, nameserver, updated_at
        ) VALUES (1, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (id) DO UPDATE SET
            api_host = EXCLUDED.api_host, api_user = EXCLUDED.api_user, token_id = EXCLUDED.token_id,
            node = EXCLUDED.node, storage = EXCLUDED.storage, bridge = EXCLUDED.bridge,
            template = EXCLUDED.template, cidr_prefix = EXCLUDED.cidr_prefix, gateway = EXCLUDED.gateway,
            nameserver = EXCLUDED.nameserver, updated_at = now()
        """,
        (
            proxmox["api_host"], proxmox["api_user"], proxmox["token_id"], proxmox["node"],
            proxmox["storage"], proxmox["bridge"], proxmox["template"], proxmox["cidr_prefix"],
            proxmox["gateway"], proxmox["nameserver"],
        ),
    )
    cluster = cfg["cluster"]
    conn.execute(
        """
        INSERT INTO cluster_settings (
            id, name, install_method, kubernetes_version, container_runtime, cni_plugin,
            pod_network_cidr, service_cidr, ansible_user, ssh_private_key_file, updated_at
        ) VALUES (1, %s, %s, %s, %s, %s, %s, %s, %s, %s, now())
        ON CONFLICT (id) DO UPDATE SET
            name = EXCLUDED.name, install_method = EXCLUDED.install_method,
            kubernetes_version = EXCLUDED.kubernetes_version, container_runtime = EXCLUDED.container_runtime,
            cni_plugin = EXCLUDED.cni_plugin, pod_network_cidr = EXCLUDED.pod_network_cidr,
            service_cidr = EXCLUDED.service_cidr, ansible_user = EXCLUDED.ansible_user,
            ssh_private_key_file = EXCLUDED.ssh_private_key_file, updated_at = now()
        """,
        (
            cluster["name"], cluster["install_method"], cluster["kubernetes_version"],
            cluster["container_runtime"], cluster["cni_plugin"], cluster["pod_network_cidr"],
            cluster["service_cidr"], cluster["ansible_user"], cluster["ssh_private_key_file"],
        ),
    )
    monitoring = cfg["monitoring"]
    conn.execute(
        """
        INSERT INTO monitoring_settings (id, environments, grafana, grafana_ingress, grafana_host, updated_at)
        VALUES (1, %s, %s, %s, %s, now())
        ON CONFLICT (id) DO UPDATE SET
            environments = EXCLUDED.environments, grafana = EXCLUDED.grafana,
            grafana_ingress = EXCLUDED.grafana_ingress, grafana_host = EXCLUDED.grafana_host,
            updated_at = now()
        """,
        (Json(monitoring["environments"]), monitoring["grafana"], monitoring["grafana_ingress"], monitoring["grafana_host"]),
    )
    cicd = cfg["cicd"]
    conn.execute(
        """
        INSERT INTO cicd_settings (id, registry, branch_dev, branch_staging, branch_prod, updated_at)
        VALUES (1, %s, %s, %s, %s, now())
        ON CONFLICT (id) DO UPDATE SET
            registry = EXCLUDED.registry, branch_dev = EXCLUDED.branch_dev,
            branch_staging = EXCLUDED.branch_staging, branch_prod = EXCLUDED.branch_prod,
            updated_at = now()
        """,
        (cicd["registry"], cicd["branches"]["dev"], cicd["branches"]["staging"], cicd["branches"]["prod"]),
    )
    conn.execute("DELETE FROM service_variables")
    conn.execute("DELETE FROM services")
    conn.execute("DELETE FROM hosts")
    conn.execute("DELETE FROM software_packages")
    conn.execute("DELETE FROM update_schedules")
    conn.execute("DELETE FROM health_checks")
    conn.execute("DELETE FROM pipelines")
    for position, host in enumerate(cfg["hosts"]):
        conn.execute(
            """
            INSERT INTO hosts (
                name, address, role, node_name, proxmox_node, vmid, cores, memory_mb, disk_gb, monitor, position
            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                host["name"], host["address"], host["role"], host["node_name"], host["proxmox_node"],
                host["vmid"], host["cores"], host["memory_mb"], host["disk_gb"], host["monitor"], position,
            ),
        )
    for position, item in enumerate(cfg["software"]):
        conn.execute(
            "INSERT INTO software_packages (name, version, scope, position) VALUES (%s, %s, %s, %s)",
            (item["name"], item["version"], item["scope"], position),
        )
    for position, item in enumerate(cfg["updates"]):
        conn.execute(
            """
            INSERT INTO update_schedules (name, cron, scope, action, enabled, position)
            VALUES (%s, %s, %s, %s, %s, %s)
            """,
            (item["name"], item["cron"], item["scope"], item["action"], item["enabled"], position),
        )
    for position, item in enumerate(monitoring["checks"]):
        conn.execute(
            "INSERT INTO health_checks (name, url, position) VALUES (%s, %s, %s)",
            (item["name"], item["url"], position),
        )
    for environment, services in cfg["services"].items():
        for position, service in enumerate(services):
            conn.execute(
                """
                INSERT INTO services (
                    environment, name, image, image_tag, replicas, cpu_request, memory_request,
                    cpu_limit, memory_limit, port, enable_ingress, ingress_host, enable_service,
                    service_type, monitor, position
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    environment, service["name"], service["image"], service["image_tag"], service["replicas"],
                    service["cpu_request"], service["memory_request"], service["cpu_limit"], service["memory_limit"],
                    service["port"], service["enable_ingress"], service["ingress_host"], service["enable_service"],
                    service["service_type"], service["monitor"], position,
                ),
            )
            for env_position, pair in enumerate(service["env"]):
                conn.execute(
                    """
                    INSERT INTO service_variables (environment, service_name, env_key, env_value, position)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    (environment, service["name"], pair["key"], pair["value"], env_position),
                )
    for position, item in enumerate(cicd["pipelines"]):
        conn.execute(
            """
            INSERT INTO pipelines (name, image, context, dockerfile, environment, auto_deploy, position)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (item["name"], item["image"], item["context"], item["dockerfile"], item["environment"], item["auto_deploy"], position),
        )


def _validate_connection(payload: dict, current: dict | None) -> dict:
    if not isinstance(payload, dict):
        raise DatabaseError("Connection settings must be an object.")
    host = str(payload.get("host", "")).strip()
    host = re.sub(r"^https?://", "", host).split("/")[0].split(":")[0]
    if not HOST_RE.fullmatch(host):
        raise DatabaseError("Database host is not valid.")
    try:
        port = int(payload.get("port", 5432))
    except (TypeError, ValueError) as exc:
        raise DatabaseError("Database port must be a whole number.") from exc
    if not 1 <= port <= 65535:
        raise DatabaseError("Database port must be between 1 and 65535.")
    database = str(payload.get("database", "")).strip()
    user = str(payload.get("user", "")).strip()
    if not IDENT_RE.fullmatch(database):
        raise DatabaseError("Database name must use letters, numbers, and underscores.")
    if not IDENT_RE.fullmatch(user):
        raise DatabaseError("Database user must use letters, numbers, and underscores.")
    password = str(payload.get("password", ""))
    if password == "" and current and current.get("password"):
        password = current["password"]
    if password == "" or "\n" in password or "\r" in password or len(password) > 200:
        raise DatabaseError("Database password is required.")
    return {"host": host, "port": port, "database": database, "user": user, "password": password}


def _connect(settings: dict) -> psycopg.Connection:
    return psycopg.connect(_dsn(settings), connect_timeout=10)


def _dsn(settings: dict) -> str:
    local = settings["host"] in {"localhost", "127.0.0.1", "::1"}
    return psycopg.conninfo.make_conninfo(
        host=settings["host"],
        port=settings["port"],
        dbname=settings["database"],
        user=settings["user"],
        password=settings["password"],
        sslmode="prefer" if local else "require",
    )


def _public_connection(saved: dict | None) -> dict:
    if saved is None:
        return {
            "configured": False,
            "connected": False,
            "host": "postgres.alpha5.finance",
            "port": 5432,
            "database": "alpha5",
            "user": "systems",
            "password_set": False,
            "version": "",
            "error": "",
        }
    return {
        "configured": True,
        "connected": False,
        "host": saved["host"],
        "port": saved["port"],
        "database": saved["database"],
        "user": saved["user"],
        "password_set": bool(saved.get("password")),
        "version": "",
        "error": "",
    }


def _public_error(exc: Exception, password: str) -> str:
    text = str(exc).strip().splitlines()[0]
    if password:
        text = text.replace(password, "*****")
    return text[:300] or "PostgreSQL rejected the connection."


def _read_local() -> dict | None:
    if not CONNECTION_PATH.is_file():
        return None
    try:
        data = json.loads(CONNECTION_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise DatabaseError("The saved PostgreSQL connection file is invalid.") from exc
    if not isinstance(data, dict):
        raise DatabaseError("The saved PostgreSQL connection file is invalid.")
    return data


def _write_local(settings: dict) -> None:
    CONNECTION_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = CONNECTION_PATH.with_suffix(".json.tmp")
    temporary.write_text(json.dumps({
        "host": settings["host"],
        "port": settings["port"],
        "database": settings["database"],
        "user": settings["user"],
        "password": settings["password"],
    }, indent=2) + "\n", encoding="utf-8", newline="\n")
    temporary.replace(CONNECTION_PATH)
