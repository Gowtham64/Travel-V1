"""
Mobile Operations Tool
Interacts with Android (ADB/Flutter) and iOS (Xcode/xcrun devicectl) environments.
Supports building, installing, capturing logs, and checking device states.
"""

from typing import Dict, Any, List, Optional
from ai.tools.terminal import run_command

def get_connected_devices() -> List[Dict[str, str]]:
    """Lists all currently connected mobile devices and emulators/simulators via Flutter."""
    res = run_command("flutter devices --machine", cwd="mobile")
    if not res["success"]:
        # Fallback to plain text
        res = run_command("flutter devices", cwd="mobile")
        lines = res["stdout"].splitlines()
        devices = []
        for line in lines:
            if "•" in line:
                parts = [p.strip() for p in line.split("•")]
                if len(parts) >= 3:
                    devices.append({
                        "name": parts[0],
                        "id": parts[1],
                        "platform": parts[2]
                    })
        return devices

    try:
        import json
        return json.loads(res["stdout"])
    except Exception:
        return []

def build_mobile_target(platform: str = "ios", release: bool = True, cwd: str = "mobile") -> Dict[str, Any]:
    """Builds the targeted mobile binary (apk, aab, or ios)."""
    mode = "--release" if release else "--debug"
    if platform == "android":
        cmd = f"flutter build apk {mode}"
    elif platform == "ios":
        cmd = f"flutter build ios {mode}"
    elif platform == "web":
        cmd = "flutter build web --release"
    else:
        return {"success": False, "error": f"Unsupported platform: {platform}"}

    return run_command(cmd, cwd=cwd, timeout=300)

def install_and_launch_ios(device_id: str, app_path: str = "build/ios/iphoneos/Runner.app", bundle_id: str = "com.gowtham.travelapp", cwd: str = "mobile") -> Dict[str, Any]:
    """Installs and launches the iOS application using Apple's xcrun devicectl."""
    install_res = run_command(f"xcrun devicectl device install app --device {device_id} {app_path}", cwd=cwd, timeout=60)
    if not install_res["success"]:
        return {"success": False, "step": "install", "details": install_res}

    launch_res = run_command(f"xcrun devicectl device process launch --device {device_id} {bundle_id}", cwd=cwd, timeout=30)
    return {
        "success": launch_res["success"],
        "install": install_res,
        "launch": launch_res
    }

def capture_ios_logs(device_id: str, bundle_id: str = "com.gowtham.travelapp", duration_seconds: int = 5) -> str:
    """Captures crash or system logs for the target bundle."""
    cmd = f"xcrun devicectl device info log --device {device_id} 2>/dev/null | grep '{bundle_id}' | tail -n 50"
    res = run_command(cmd, timeout=duration_seconds + 5)
    return res["stdout"]

if __name__ == "__main__":
    devs = get_connected_devices()
    print(f"Connected devices detected: {len(devs)}")
