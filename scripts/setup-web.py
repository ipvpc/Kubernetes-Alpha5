import argparse
import os
import shutil
import subprocess
import sys
import venv
from pathlib import Path


def setup_deployment() -> None:
    if os.name != "nt":
        raise SystemExit("Automatic deployment-tool setup currently supports Windows.")

    tools = (
        ("terraform", "Hashicorp.Terraform", ["version"]),
        ("kubectl", "Kubernetes.kubectl", ["version", "--client"]),
        ("helm", "Helm.Helm", ["version", "--short"]),
    )
    missing = []
    for command, package, version_args in tools:
        if not shutil.which(command):
            if not shutil.which("winget"):
                raise SystemExit("Install Windows App Installer to enable WinGet, then rerun setup.")
            subprocess.run(["winget", "install", "--id", package, "--exact", "--source", "winget"], check=True)
            if not shutil.which(command):
                missing.append(command)
                continue
        subprocess.run([command, *version_args], check=True)

    wsl = ["wsl.exe", "--distribution", "Ubuntu-24.04", "--exec"]
    if subprocess.run([*wsl, "true"]).returncode:
        subprocess.run(["wsl.exe", "--install", "--distribution", "Ubuntu-24.04", "--no-launch"], check=True)
        raise SystemExit("Open Ubuntu 24.04 to finish first-time setup, then rerun this command.")

    packages = ["ansible", "python3-proxmoxer", "python3-requests", "openssh-client"]
    if subprocess.run([*wsl, "dpkg", "-s", *packages], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        subprocess.run([*wsl, "sudo", "apt-get", "update"], check=True)
        subprocess.run([*wsl, "sudo", "apt-get", "install", "-y", *packages], check=True)
    subprocess.run([*wsl, "ansible-playbook", "--version"], check=True)
    subprocess.run([*wsl, "ansible-doc", "community.general.proxmox_kvm"], stdout=subprocess.DEVNULL, check=True)
    if missing:
        raise SystemExit(f"Open a new PowerShell window and rerun setup to verify {', '.join(missing)}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Set up Alpha5 Deployment Center.")
    parser.add_argument("--deploy", action="store_true", help="Also install deployment tools on Windows.")
    args = parser.parse_args()
    if sys.version_info < (3, 10):
        raise SystemExit("Install Python 3.10 or newer, then rerun setup.")

    root = Path(__file__).resolve().parent.parent
    environment = root / ".venv"
    interpreter = environment / (
        "Scripts/python.exe" if os.name == "nt" else "bin/python"
    )
    if not interpreter.is_file():
        venv.create(environment, with_pip=True)

    subprocess.run(
        [str(interpreter), "-m", "pip", "install", "-r", str(root / "web/requirements.txt")],
        check=True,
    )
    subprocess.run([str(interpreter), "-m", "pip", "check"], check=True)
    subprocess.run([str(interpreter), "-c", "import checks, config_store, database, server"], cwd=root / "web", check=True)
    print(f'Start from the repository with "{interpreter}" -u web/server.py')
    if args.deploy:
        setup_deployment()


if __name__ == "__main__":
    main()
