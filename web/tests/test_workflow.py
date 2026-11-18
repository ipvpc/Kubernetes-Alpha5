"""The generated deploy job must apply console settings, not only terraform.tfvars."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from config_store import _workflow


def _config(auto_deploy: bool) -> dict:
    return {
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
                    "auto_deploy": auto_deploy,
                }
            ],
        }
    }


class WorkflowVarFileTests(unittest.TestCase):
    def test_auto_deploy_applies_console_file_after_base_tfvars(self) -> None:
        text = _workflow(_config(True))
        apply_lines = [line.strip() for line in text.splitlines() if "terraform apply" in line]
        self.assertEqual(len(apply_lines), 1)
        apply = apply_lines[0]
        base = "../environments/dev/terraform.tfvars"
        console = "../environments/dev/platform.auto.tfvars.json"
        self.assertIn(base, apply)
        self.assertIn(console, apply)
        self.assertLess(apply.index(base), apply.index(console))

    def test_build_only_pipeline_does_not_apply(self) -> None:
        text = _workflow(_config(False))
        self.assertNotIn("terraform apply", text)


if __name__ == "__main__":
    unittest.main()
