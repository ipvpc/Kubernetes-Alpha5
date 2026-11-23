import os
import subprocess
import sys
import venv
from pathlib import Path


def main() -> None:
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


if __name__ == "__main__":
    main()
