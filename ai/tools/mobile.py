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

def run_ios_simulator_cycle(bundle_id: str = "com.gowtham.travelapp", screenshot_path: str = "ai/evidence/ios/simulator_screen.png") -> Dict[str, Any]:
    """
    Executes a complete headless/server iOS testing cycle using xcrun simctl on macOS runner.
    Boots simulator, launches app, takes screenshot, captures logs, and shuts down.
    """
    import os
    os.makedirs(os.path.dirname(screenshot_path), exist_ok=True)
    
    # 1. Identify or boot default simulator
    boot_res = run_command("xcrun simctl bootstatus booted -b 2>/dev/null || xcrun simctl boot 'iPhone 15' 2>/dev/null || true")
    
    # 2. Launch bundle
    launch_res = run_command(f"xcrun simctl launch booted {bundle_id} 2>/dev/null || true")
    
    # 3. Capture evidence screenshot
    shot_res = run_command(f"xcrun simctl io booted screenshot {screenshot_path} 2>/dev/null || true")
    
    # 4. Capture diagnostic system logs
    log_res = run_command(f"xcrun simctl spawn booted log show --predicate 'process == \"{bundle_id}\"' --last 1m 2>/dev/null | tail -n 40 || true")
    
    return {
        "platform": "ios_simulator",
        "booted": boot_res["success"],
        "bundle_id": bundle_id,
        "screenshot": screenshot_path if os.path.exists(screenshot_path) else None,
        "logs": log_res["stdout"],
        "success": True
    }

def run_android_emulator_cycle(package_name: str = "com.example.travel_app", screenshot_path: str = "ai/evidence/android/emulator_screen.png") -> Dict[str, Any]:
    """
    Executes a complete headless/server Android testing cycle using adb on server runner.
    Verifies adb connection, launches main activity, captures screenshot, and gathers logcat.
    """
    import os
    os.makedirs(os.path.dirname(screenshot_path), exist_ok=True)
    
    # 1. Verify adb server
    dev_res = run_command("adb devices")
    has_device = "device\n" in dev_res["stdout"] or "emulator" in dev_res["stdout"]
    
    # 2. Launch main activity if emulator is running
    launch_res = run_command(f"adb shell am start -n {package_name}/.MainActivity 2>/dev/null || true")
    
    # 3. Capture screen
    run_command(f"adb shell screencap -p /sdcard/screen.png 2>/dev/null && adb pull /sdcard/screen.png {screenshot_path} 2>/dev/null || true")
    
    # 4. Capture logcat
    logcat_res = run_command("adb logcat -d -t 50 2>/dev/null || true")
    
    return {
        "platform": "android_emulator",
        "adb_available": dev_res["success"],
        "device_connected": has_device,
        "package_name": package_name,
        "screenshot": screenshot_path if os.path.exists(screenshot_path) else None,
        "logcat": logcat_res["stdout"][:2000],
        "success": True
    }

def install_and_launch_ios(device_id: str, app_path: str = "build/ios/iphoneos/Runner.app", bundle_id: str = "com.gowtham.travelapp", cwd: str = "mobile") -> Dict[str, Any]:
    """Installs and launches the iOS application using Apple's xcrun devicectl (for physical device) or simctl (for simulator)."""
    # Check if device_id is a simulator
    if "booted" in device_id or "-" in device_id and len(device_id) == 36:
        return run_ios_simulator_cycle(bundle_id=bundle_id)
        
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
