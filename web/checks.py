"""Reachability checks for hosts, the Proxmox API, and HTTP health URLs."""

from __future__ import annotations

import socket
import ssl
import threading
import time
import urllib.error
import urllib.request

import config_store

_CACHE: dict = {"at": 0.0, "value": None}
_TTL_SECONDS = 5.0


def invalidate() -> None:
    _CACHE["value"] = None


def collect(cfg: dict | None = None, force: bool = False) -> list[dict]:
    now = time.monotonic()
    if not force and _CACHE["value"] is not None and now - _CACHE["at"] < _TTL_SECONDS:
        return _CACHE["value"]

    current = cfg if cfg is not None else config_store.load()
    jobs = []
    for host in current["hosts"]:
        jobs.append(_tcp_job(host["name"], "ssh", host["address"], 22))
        if host["monitor"]:
            jobs.append(_tcp_job(host["name"], "node-exporter", host["address"], 9100))
    api_host = current["proxmox"]["api_host"]
    if api_host:
        jobs.append(_tcp_job("proxmox", "proxmox-api", api_host, 8006))
    for check in config_store.http_checks(current):
        jobs.append(_http_job(check["name"], check["url"]))

    results: list[dict | None] = [None] * len(jobs)
    threads = []
    for index, (meta, job) in enumerate(jobs):
        def run(item=job, slot=index) -> None:
            results[slot] = item()
        thread = threading.Thread(target=run, daemon=True)
        thread.start()
        threads.append(thread)
    for thread in threads:
        thread.join(1.2)
    finished = []
    for index, result in enumerate(results):
        if result is None:
            finished.append({**jobs[index][0], "reachable": False, "detail": "Timed out"})
        else:
            finished.append(result)
    _CACHE["at"] = time.monotonic()
    _CACHE["value"] = finished
    return finished


def _tcp_job(name: str, kind: str, host: str, port: int):
    meta = {"name": name, "kind": kind, "target": f"{host}:{port}"}

    def run() -> dict:
        reachable = _tcp_open(host, port)
        detail = "Open" if reachable else "No route from this console"
        return {**meta, "reachable": reachable, "detail": detail}

    return meta, run


def _http_job(name: str, url: str):
    meta = {"name": name, "kind": "http", "target": url}

    def run() -> dict:
        reachable = _http_open(url)
        detail = "Answered" if reachable else "No route from this console"
        return {**meta, "reachable": reachable, "detail": detail}

    return meta, run


def _tcp_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.8):
            return True
    except OSError:
        return False


def _http_open(url: str) -> bool:
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=0.8) as response:
            return response.status < 500
    except urllib.error.HTTPError as exc:
        return exc.code < 500
    except urllib.error.URLError as exc:
        reason = exc.reason
        text = str(reason).lower()
        return isinstance(reason, ssl.SSLError) or "certificate" in text or "ssl" in text
    except OSError:
        return False
