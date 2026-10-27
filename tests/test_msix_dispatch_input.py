"""Guard GitHub Actions 3D MSIX dispatch inputs against PowerShell injection."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "msix-export.yml"
SCRIPT = ROOT / "tools" / "build_godot_store_msix.ps1"


class MsixDispatchInputTests(unittest.TestCase):
    def test_dispatch_slug_is_not_interpolated_into_powershell_source(self):
        workflow = WORKFLOW.read_text(encoding="utf-8")
        step = workflow.split("- name: Build real Godot payload and unsigned MSIX", 1)[1]
        step = step.split("\n      - name:", 1)[0]
        self.assertIn("GAME_SLUG: " + "${{ inputs.slug }}", step)
        self.assertIn("-Slug $env:GAME_SLUG", step)
        command = step.split("run: |", 1)[1]
        self.assertNotIn("${{", command)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell not installed")
    def test_shell_metacharacters_are_rejected_as_slug_data(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "injected.txt"
            payload = "demo'; Set-Content -LiteralPath '" + str(marker) + "' -Value injected; #"
            environment = dict(os.environ, GAME_SLUG=payload)
            result = subprocess.run(
                ["pwsh", "-NoProfile", "-NonInteractive", "-Command",
                 "& ./tools/build_godot_store_msix.ps1 -Slug $env:GAME_SLUG"],
                cwd=ROOT, env=environment, capture_output=True, text=True, timeout=20,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists(), "malicious dispatch input executed as code")


if __name__ == "__main__":
    unittest.main()
