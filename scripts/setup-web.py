import argparse
import os
import platform
import shutil
import subprocess
import sys
import venv
from pathlib import Path


DEPLOY_TOOLS = (
    ("terraform", "Hashicorp.Terraform", ["version"]),
    ("kubectl", "Kubernetes.kubectl", ["version", "--client"]),
    ("helm", "Helm.Helm", ["version", "--short"]),
)


def install_ubuntu_packages(prefix: list[str], packages: list[str]) -> None:
    missing = []
    for package in packages:
        status = subprocess.run(
            [*prefix, "dpkg-query", "-W", "-f=${Status}", package],
            capture_output=True,
        )
        if status.returncode or status.stdout != b"install ok installed":
            missing.append(package)
    if missing:
        subprocess.run([*prefix, "sudo", "apt-get", "update"], check=True)
        subprocess.run([*prefix, "sudo", "apt-get", "install", "-y", *missing], check=True)


def setup_ansible(prefix: list[str]) -> None:
    install_ubuntu_packages(prefix, ["ansible", "python3-proxmoxer", "python3-requests", "openssh-client"])
    subprocess.run([*prefix, "ansible-playbook", "--version"], check=True)
    subprocess.run([*prefix, "ansible-doc", "community.general.proxmox_kvm"], stdout=subprocess.DEVNULL, check=True)


def setup_ubuntu_deployment() -> None:
    if not all(shutil.which(command) for command, _, _ in DEPLOY_TOOLS):
        install_ubuntu_packages([], ["snapd"])
    for command, _, version_args in DEPLOY_TOOLS:
        executable = shutil.which(command)
        if executable:
            subprocess.run([executable, *version_args], check=True)
            continue
        if subprocess.run(["snap", "list", command], capture_output=True).returncode:
            subprocess.run(["sudo", "snap", "install", command, "--classic"], check=True)
        subprocess.run(["snap", "run", command, *version_args], check=True)
    setup_ansible([])


def setup_deployment(distribution: str) -> None:
    if os.name != "nt":
        if sys.platform == "linux" and platform.freedesktop_os_release().get("ID") == "ubuntu":
            setup_ubuntu_deployment()
            return
        raise SystemExit("Automatic deployment-tool setup supports Ubuntu and Windows.")

    missing = []
    for command, package, version_args in DEPLOY_TOOLS:
        if not shutil.which(command):
            if not shutil.which("winget"):
                raise SystemExit("Install Windows App Installer to enable WinGet, then rerun setup.")
            subprocess.run(["winget", "install", "--id", package, "--exact", "--source", "winget"], check=True)
            if not shutil.which(command):
                missing.append(command)
                continue
        subprocess.run([command, *version_args], check=True)

    wsl = ["wsl.exe", "--distribution", distribution, "--exec"]
    if subprocess.run([*wsl, "true"]).returncode:
        if distribution != "Ubuntu-24.04":
            raise SystemExit(f"Could not start WSL distribution {distribution}.")
        subprocess.run(["wsl.exe", "--install", "--distribution", "Ubuntu-24.04", "--no-launch"], check=True)
        raise SystemExit("Open Ubuntu 24.04 to finish first-time setup, then rerun this command.")

    setup_ansible(wsl)
    if missing:
        raise SystemExit(f"Open a new PowerShell window and rerun setup to verify {', '.join(missing)}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Set up Alpha5 Deployment Center.")
    parser.add_argument("--deploy", action="store_true", help="Also install deployment tools on Ubuntu or Windows.")
    parser.add_argument("--wsl-distro", default="Ubuntu-24.04", help="Use an existing Ubuntu 24.04 WSL distribution by name.")
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
        setup_deployment(args.wsl_distro)


if __name__ == "__main__":
    main()
