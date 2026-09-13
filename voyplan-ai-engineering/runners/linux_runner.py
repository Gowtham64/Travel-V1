"""
Linux Execution Runner.
Controls real Web browser tests, Backend API tests, and real Android Emulator / ADB if provisioned.
ABSOLUTE NO-MOCK RULE: If Android SDK / Emulator hardware virtualization is absent,
reports INFRASTRUCTURE CAPABILITY NOT AVAILABLE.
"""

import os
import shutil
import subprocess
from typing import Dict, Any, List, Optional
from runners.base_runner import BaseRunner

class LinuxRunner(BaseRunner):
    def __init__(self, workspace_path: str):
        super().__init__(runner_id="runner-linux-01", name="Linux Server Runner", platform="linux")
        self.workspace_path = workspace_path

    def get_capabilities(self) -> Dict[str, Any]:
        """Inspects actual server capabilities."""
        has_node = shutil.which("node") is not None
        has_npm = shutil.which("npm") is not None
        has_python = shutil.which("python3") is not None
        has_adb = shutil.which("adb") is not None
        has_emulator = shutil.which("emulator") is not None
        
        android_devices = []
        if has_adb:
            try:
                res = subprocess.run(["adb", "devices"], stdout=subprocess.PIPE, text=True, timeout=5)
                lines = res.stdout.strip().splitlines()[1:]
                android_devices = [l.split()[0] for l in lines if "\tdevice" in l]
            except Exception:
                pass

        available = []
        if has_node and has_npm:
            available.append("web-playwright")
            available.append("backend-jest")
        if has_python:
            available.append("python-backend")
        if has_adb and android_devices:
            available.append("android-adb")
        if has_emulator:
            available.append("android-emulator")

        return {
            "status": "ONLINE" if available else "OFFLINE",
            "capabilities": available,
            "available_devices": android_devices,
            "has_adb": has_adb,
            "has_emulator": has_emulator
        }

    def run_backend_test(self, test_pattern: str = "destinationBoundaries") -> Dict[str, Any]:
        """Executes real Jest backend regression tests."""
        npm_bin = shutil.which("npm") or "npm"
        backend_dir = os.path.join(self.workspace_path, "backend")
        if not os.path.exists(backend_dir):
            return {
                "success": False,
                "status": "BLOCKED",
                "error": f"Backend directory not found at {backend_dir}",
                "exit_code": 1
            }
        
        cmd = [npm_bin, "test", "--", f"--testPathPattern={test_pattern}", "--forceExit"]
        res = self.execute_command(cmd, cwd=backend_dir, timeout_sec=60)
        res["status"] = "PASS" if res["success"] else "FAIL"
        return res

    def run_android_test(self, test_name: str, apk_path: str = None) -> Dict[str, Any]:
        """Executes real Android test using ADB if device is connected."""
        caps = self.get_capabilities()
        if not caps["has_adb"]:
            return {
                "success": False,
                "status": "BLOCKED",
                "error": "INFRASTRUCTURE CAPABILITY NOT AVAILABLE - ANDROID SDK / ADB NOT FOUND ON RUNNER",
                "exit_code": 127
            }
        
        devices = caps["available_devices"]
        if not devices:
            return {
                "success": False,
                "status": "BLOCKED",
                "error": "INFRASTRUCTURE CAPABILITY NOT AVAILABLE - NO ACTIVE ANDROID EMULATOR / DEVICE CONNECTED",
                "exit_code": 126
            }

        target_device = devices[0]
        # Real ADB execution
        if apk_path and os.path.exists(apk_path):
            install_res = self.execute_command(["adb", "-s", target_device, "install", "-r", apk_path], timeout_sec=60)
            if not install_res["success"]:
                return {
                    "success": False,
                    "status": "FAIL",
                    "error": f"APK installation failed on device {target_device}: {install_res['stderr']}",
                    "exit_code": install_res["exit_code"],
                    "stdout": install_res["stdout"],
                    "stderr": install_res["stderr"]
                }

        # Launch app
        launch_res = self.execute_command(["adb", "-s", target_device, "shell", "monkey", "-p", "io.github.gowtham64.travelapp", "-c", "android.intent.category.LAUNCHER", "1"], timeout_sec=15)
        logcat_res = self.execute_command(["adb", "-s", target_device, "logcat", "-d", "-t", "50"], timeout_sec=10)
        
        return {
            "success": launch_res["success"],
            "status": "PASS" if launch_res["success"] else "FAIL",
            "device": target_device,
            "stdout": launch_res["stdout"],
            "stderr": launch_res["stderr"],
            "logcat": logcat_res["stdout"]
        }
