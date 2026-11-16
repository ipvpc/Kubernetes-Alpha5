#!/usr/bin/env python3
"""Alpha5 control plane.

Serves the settings UI, Kubernetes probe endpoints, and the API that writes
Terraform and Ansible configuration.

Run from the repository:
    python web/server.py
"""

from __future__ import annotations

import json
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

import checks
import config_store
import database

ROOT = Path(__file__).resolve().parent
STATIC_DIR = ROOT / "static"
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "3000"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        route = parsed.path
        if route == "/health":
            self._send_json(200, {"status": "ok"})
            return
        if route == "/ready":
            self._send_json(200, {"status": "ready"})
            return
        if route == "/api/config":
            self._guard(self._config_response)
            return
        if route == "/api/health":
            force = "fresh=1" in parsed.query
            self._guard(lambda: self._send_json(200, {"checks": checks.collect(force=force)}))
            return
        if route.startswith("/api/"):
            self._send_json(404, {"error": "Unknown API route"})
            return
        super().do_GET()

    def do_POST(self) -> None:
        self._mutate(self._post)

    def do_PUT(self) -> None:
        self._mutate(self._put)

    def do_DELETE(self) -> None:
        self._mutate(self._delete)

    def _config_response(self) -> None:
        info = database.status()
        if not info["connected"]:
            self._send_json(200, {
                "config": None,
                "preview": config_store.preview(),
                "database": info,
                "generated": [],
            })
            return
        cfg = config_store.load()
        self._send_json(200, {
            "config": cfg,
            "database": database.status(),
            "generated": config_store.generated_paths(),
        })

    def _post(self, route: str, payload: dict) -> None:
        if route == "/api/hosts":
            self._saved(config_store.add_host(payload), "Host added")
            return
        if route == "/api/software":
            self._saved(config_store.add_software(payload), "Package added")
            return
        if route == "/api/updates":
            self._saved(config_store.add_update(payload), "Update schedule added")
            return
        if route == "/api/checks":
            self._saved(config_store.add_check(payload), "Health check added")
            return
        if route == "/api/services":
            self._saved(config_store.add_service(payload), "Service added")
            return
        if route == "/api/pipelines":
            self._saved(config_store.add_pipeline(payload), "Pipeline added")
            return
        self._send_json(404, {"error": "Unknown API route"})

    def _put(self, route: str, payload: dict) -> None:
        parts = self._parts(route)
        if route == "/api/database":
            self._save_database(payload)
            return
        if route == "/api/proxmox":
            self._saved(config_store.save_proxmox(payload), "Proxmox settings saved")
            return
        if route == "/api/cluster":
            self._saved(config_store.save_cluster(payload), "Cluster settings saved")
            return
        if route == "/api/monitoring":
            self._saved(config_store.save_monitoring(payload), "Monitoring settings saved")
            return
        if route == "/api/cicd":
            self._saved(config_store.save_cicd(payload), "CI/CD settings saved")
            return
        if len(parts) == 3 and parts[1] == "hosts":
            self._saved(config_store.replace_host(parts[2], payload), "Host saved")
            return
        if len(parts) == 3 and parts[1] == "software":
            self._saved(config_store.replace_software(parts[2], payload), "Package saved")
            return
        if len(parts) == 3 and parts[1] == "updates":
            self._saved(config_store.replace_update(parts[2], payload), "Update schedule saved")
            return
        if len(parts) == 3 and parts[1] == "pipelines":
            self._saved(config_store.replace_pipeline(parts[2], payload), "Pipeline saved")
            return
        if len(parts) == 4 and parts[1] == "services":
            self._saved(config_store.replace_service(parts[2], parts[3], payload), "Service saved")
            return
        self._send_json(404, {"error": "Unknown API route"})

    def _delete(self, route: str, _payload: dict) -> None:
        parts = self._parts(route)
        if len(parts) == 3 and parts[1] == "hosts":
            self._saved(config_store.delete_host(parts[2]), "Host removed")
            return
        if len(parts) == 3 and parts[1] == "software":
            self._saved(config_store.delete_software(parts[2]), "Package removed")
            return
        if len(parts) == 3 and parts[1] == "updates":
            self._saved(config_store.delete_update(parts[2]), "Update schedule removed")
            return
        if len(parts) == 3 and parts[1] == "checks":
            self._saved(config_store.delete_check(parts[2]), "Health check removed")
            return
        if len(parts) == 3 and parts[1] == "pipelines":
            self._saved(config_store.delete_pipeline(parts[2]), "Pipeline removed")
            return
        if len(parts) == 4 and parts[1] == "services":
            self._saved(config_store.delete_service(parts[2], parts[3]), "Service removed")
            return
        self._send_json(404, {"error": "Unknown API route"})

    def _save_database(self, payload: dict) -> None:
        info = database.save_connection(payload)
        cfg = None
        imported = False
        if info["connected"] and database.load_config() is None:
            cfg = config_store.seed_and_store()
            imported = True
        elif info["connected"]:
            cfg = config_store.load()
        message = "PostgreSQL connection saved"
        if imported:
            message += ". Existing console settings were imported"
        checks.invalidate()
        self._send_json(200, {
            "message": message,
            "config": cfg,
            "database": database.status(),
            "generated": config_store.generated_paths() if cfg else [],
        })

    def _saved(self, cfg: dict, message: str) -> None:
        checks.invalidate()
        self._send_json(200, {
            "message": f"{message} and saved to PostgreSQL",
            "config": cfg,
            "database": database.status(),
            "generated": config_store.generated_paths(),
        })

    def _mutate(self, method) -> None:
        route = urlparse(self.path).path
        try:
            payload = self._read_json()
            method(route, payload)
        except (config_store.ConfigError, database.DatabaseError) as exc:
            self._send_json(400, {"error": str(exc)})
        except json.JSONDecodeError:
            self._send_json(400, {"error": "Request body must be JSON"})
        except ValueError as exc:
            self._send_json(400, {"error": str(exc)})

    def _guard(self, method) -> None:
        try:
            method()
        except (config_store.ConfigError, database.DatabaseError) as exc:
            self._send_json(400, {"error": str(exc)})

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length > 1_000_000:
            raise ValueError("Request body is too large")
        if length <= 0:
            return {}
        data = json.loads(self.rfile.read(length).decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("Request body must be an object")
        return data

    def _parts(self, route: str) -> list[str]:
        return [unquote(part) for part in route.strip("/").split("/")]

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args) -> None:
        print(f"[alpha5] {self.address_string()} {fmt % args}", flush=True)


def main() -> None:
    missing = [name for name in ("index.html", "styles.css", "app.js") if not (STATIC_DIR / name).is_file()]
    if missing:
        raise SystemExit(f"Missing static files: {', '.join(missing)}")
    if config_store.repo_ready():
        config_store.ensure_exported()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Alpha5 console listening on http://127.0.0.1:{PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping Alpha5 console", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
