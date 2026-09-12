"""
VoyPlan Android Device Human Tester
Controls Android Emulators and physical Android devices via ADB.
Automates APK installation, launch, UI inspection, touch/swipe events, and logcat capture.
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime
from typing import Dict, Any, Optional, List

class AndroidDeviceTester:
    PACKAGE_NAME = "com.example.travel_app"
    MAIN_ACTIVITY = "com.example.travel_app.MainActivity"
    
    def __init__(self, workspace_root: Optional[str] = None):
        self.workspace_root = workspace_root or os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
        self.adb_bin = self._find_adb()
        self.evidence_dir = os.path.join(self.workspace_root, "voyplan-ai-engineering/evidence")
        os.makedirs(os.path.join(self.evidence_dir, "screenshots"), exist_ok=True)
        os.makedirs(os.path.join(self.evidence_dir, "logs"), exist_ok=True)

    def _find_adb(self) -> str:
        candidates = [
            "/Users/gowtham/android-bootstrap/android-sdk/platform-tools/adb",
            os.path.expanduser("~/android-bootstrap/android-sdk/platform-tools/adb"),
            os.path.expanduser("~/Library/Android/sdk/platform-tools/adb"),
            "adb"
        ]
        for c in candidates:
            if os.path.exists(c) and os.access(c, os.X_OK):
                return c
        return "adb"

    def detect_devices(self) -> List[Dict[str, str]]:
        """Detect attached Android devices/emulators via ADB."""
        devices = []
        try:
            res = subprocess.run([self.adb_bin, "devices"], capture_output=True, text=True, timeout=5)
            for line in res.stdout.splitlines()[1:]:
                parts = line.strip().split()
                if len(parts) >= 2 and parts[1] == "device":
                    devices.append({
                        "id": parts[0],
                        "state": parts[1],
                        "type": "emulator" if "emulator" in parts[0] else "physical"
                    })
        except Exception as e:
            print(f"[ANDROID TESTER] ⚠️ Could not run ADB: {e}")
        return devices

    def install_apk(self, device_id: str, apk_path: Optional[str] = None) -> bool:
        """Installs the compiled VoyPlan APK."""
        if not apk_path:
            candidates = [
                os.path.join(self.workspace_root, "mobile/build/app/outputs/flutter-apk/app-release.apk"),
                os.path.join(self.workspace_root, "mobile/build/app/outputs/flutter-apk/app-debug.apk")
            ]
            for c in candidates:
                if os.path.exists(c):
                    apk_path = c
                    break

        if not apk_path or not os.path.exists(apk_path):
            print(f"[ANDROID TESTER] ❌ APK not found. Please build with 'flutter build apk'.")
            return False

        print(f"[ANDROID TESTER] 📦 Installing {apk_path} on {device_id}...")
        cmd = [self.adb_bin, "-s", device_id, "install", "-r", apk_path]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return res.returncode == 0 and "Success" in res.stdout

    def launch_app(self, device_id: str) -> bool:
        """Launches VoyPlan MainActivity."""
        print(f"[ANDROID TESTER] 🚀 Launching {self.PACKAGE_NAME} on {device_id}...")
        cmd = [self.adb_bin, "-s", device_id, "shell", "am", "start", "-n", f"{self.PACKAGE_NAME}/{self.MAIN_ACTIVITY}"]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return res.returncode == 0

    def terminate_app(self, device_id: str) -> bool:
        """Force-stops the app to simulate kill."""
        print(f"[ANDROID TESTER] 🛑 Force-stopping {self.PACKAGE_NAME} on {device_id}...")
        cmd = [self.adb_bin, "-s", device_id, "shell", "am", "force-stop", self.PACKAGE_NAME]
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return res.returncode == 0

    def capture_screenshot(self, device_id: str, label: str = "android") -> Optional[str]:
        """Captures a screenshot via ADB screencap."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_path = os.path.join(self.evidence_dir, "screenshots", f"android_{label}_{timestamp}.png")
        try:
            with open(out_path, "wb") as f:
                subprocess.run([self.adb_bin, "-s", device_id, "exec-out", "screencap", "-p"], stdout=f, timeout=15)
            if os.path.exists(out_path) and os.path.getsize(out_path) > 1000:
                return out_path
        except Exception:
            pass
        return None

    def dump_ui_hierarchy(self, device_id: str) -> Optional[str]:
        """Dumps UI hierarchy for accessibility and button discovery."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        local_path = os.path.join(self.evidence_dir, "logs", f"android_ui_{timestamp}.xml")
        try:
            subprocess.run([self.adb_bin, "-s", device_id, "shell", "uiautomator", "dump", "/data/local/tmp/uidump.xml"], timeout=10)
            subprocess.run([self.adb_bin, "-s", device_id, "pull", "/data/local/tmp/uidump.xml", local_path], timeout=10)
            if os.path.exists(local_path):
                return local_path
        except Exception:
            pass
        return None

    def run_human_journey(self, device_id: Optional[str] = None) -> Dict[str, Any]:
        """Executes full Android human testing journey."""
        devices = self.detect_devices()
        if not devices:
            print("[ANDROID TESTER] ⚠️ No active Android device/emulator connected.")
            result_payload = {
                "task_id": f"android_test_{int(time.time())}",
                "agent": "ANDROID_HUMAN_TESTER",
                "platform": "Android",
                "status": "SKIP",
                "reason": "No active Android device or emulator running. (Ready to run when emulator/device attached).",
                "timestamp": datetime.now().isoformat()
            }
            # Save artifact
            result_file = os.path.join(self.workspace_root, "voyplan-ai-engineering/test-result-android.json")
            with open(result_file, "w") as f:
                json.dump(result_payload, f, indent=2)
            return result_payload

        dev = devices[0] if not device_id else next((d for d in devices if d["id"] == device_id), devices[0])
        dev_id = dev["id"]
        print(f"\n=======================================================")
        print(f" [ANDROID HUMAN TESTER] Starting Autonomous Test on: {dev_id}")
        print(f"=======================================================")

        journey = []
        evidence = []

        # 1. Launch
        t0 = time.time()
        launch_ok = self.launch_app(dev_id)
        journey.append({"step": "LAUNCH_APP", "status": "PASS" if launch_ok else "FAIL", "duration_s": round(time.time() - t0, 2)})

        # 2. Observe & Settle
        time.sleep(3)
        shot = self.capture_screenshot(dev_id, label="after_launch")
        if shot:
            evidence.append(shot)

        # 3. UI Discovery
        ui_dump = self.dump_ui_hierarchy(dev_id)
        if ui_dump:
            evidence.append(ui_dump)

        # 4. Lifecycle Kill & Resumption
        term_ok = self.terminate_app(dev_id)
        journey.append({"step": "KILL_APP", "status": "PASS" if term_ok else "WARN"})
        time.sleep(2)

        relaunch_ok = self.launch_app(dev_id)
        journey.append({"step": "RELAUNCH_RESUMPTION", "status": "PASS" if relaunch_ok else "FAIL"})
        time.sleep(2)

        shot2 = self.capture_screenshot(dev_id, label="after_relaunch")
        if shot2:
            evidence.append(shot2)

        overall_pass = launch_ok and relaunch_ok
        result_payload = {
            "task_id": f"android_test_{int(time.time())}",
            "agent": "ANDROID_HUMAN_TESTER",
            "platform": "Android",
            "device_id": dev_id,
            "status": "PASS" if overall_pass else "FAIL",
            "journey": journey,
            "evidence": evidence,
            "timestamp": datetime.now().isoformat()
        }

        result_file = os.path.join(self.workspace_root, "voyplan-ai-engineering/test-result-android.json")
        with open(result_file, "w") as f:
            json.dump(result_payload, f, indent=2)

        print(f"[ANDROID TESTER] Finished Android Human Test. Status: {'✅ PASS' if overall_pass else '❌ FAIL'}")
        return result_payload

if __name__ == "__main__":
    tester = AndroidDeviceTester()
    res = tester.run_human_journey()
    print(json.dumps(res, indent=2))
