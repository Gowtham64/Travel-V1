"""
Web Execution Runner.
Controls real Chromium / Playwright browser tests.
ABSOLUTE NO-MOCK RULE: Runs actual browser commands. If Playwright or browser binaries
are missing, reports INFRASTRUCTURE CAPABILITY NOT AVAILABLE.
"""

import os
import sys
import shutil
import time
from typing import Dict, Any, List, Optional
from runners.base_runner import BaseRunner

class WebRunner(BaseRunner):
    def __init__(self, workspace_path: str):
        super().__init__(runner_id="runner-web-01", name="Remote Web Browser Runner", platform="web")
        self.workspace_path = workspace_path
        self.artifacts_dir = os.path.join(self.workspace_path, "voyplan-ai-engineering", "artifacts", "web")
        os.makedirs(self.artifacts_dir, exist_ok=True)

    def get_capabilities(self) -> Dict[str, Any]:
        has_node = shutil.which("node") is not None
        has_npx = shutil.which("npx") is not None
        has_python = shutil.which("python3") is not None
        return {
            "status": "ONLINE" if (has_node or has_python) else "OFFLINE",
            "capabilities": ["playwright-chromium", "headless-browser"],
            "has_node": has_node,
            "has_npx": has_npx
        }

    def run_web_navigation_test(self, target_url: str = "https://voyplan.in") -> Dict[str, Any]:
        """Executes a real Python Playwright navigation script."""
        script_code = f"""
import sys, time
try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print('PLAYWRIGHT_NOT_INSTALLED')
    sys.exit(2)

try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto('{target_url}', timeout=30000)
        title = page.title()
        screenshot_path = '{self.artifacts_dir}/web_live_{int(time.time())}.png'
        page.screenshot(path=screenshot_path)
        browser.close()
        print('SUCCESS: Title=' + str(title) + ' Screenshot=' + screenshot_path)
        sys.exit(0)
except Exception as e:
    print('PLAYWRIGHT_ERROR: ' + str(e))
    sys.exit(1)
"""
        py_bin = sys.executable
        res = self.execute_command([py_bin, "-c", script_code], timeout_sec=45)
        
        if "PLAYWRIGHT_NOT_INSTALLED" in res["stdout"]:
            return {
                "success": False,
                "status": "BLOCKED",
                "error": "INFRASTRUCTURE CAPABILITY NOT AVAILABLE - PLAYWRIGHT PYTHON PACKAGE NOT INSTALLED",
                "exit_code": 2,
                "stdout": res["stdout"],
                "stderr": res["stderr"],
                "duration": res["duration"]
            }
        
        if res["exit_code"] != 0:
            return {
                "success": False,
                "status": "FAIL",
                "error": res["stdout"] or res["stderr"],
                "exit_code": res["exit_code"],
                "stdout": res["stdout"],
                "stderr": res["stderr"],
                "duration": res["duration"]
            }

        return {
            "success": True,
            "status": "PASS",
            "stdout": res["stdout"].strip(),
            "stderr": res["stderr"],
            "duration": res["duration"],
            "url": target_url
        }
