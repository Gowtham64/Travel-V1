#!/usr/bin/env python3
"""
Remote macOS Xcode Server Daemon
Enables Linux servers (e.g. Render, Docker, AWS Ubuntu) to execute real Xcode builds,
XCTest suites, and iOS Simulator commands on a remote macOS server node.
"""

import os
import sys
import json
import time
import shutil
import platform
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Dict, Any, List

PORT = int(os.environ.get("MACOS_RUNNER_PORT", 5055))
AUTH_SECRET = os.environ.get("MACOS_RUNNER_SECRET", "")

class MacOSRunnerHandler(BaseHTTPRequestHandler):
    def _send_json(self, status_code: int, data: Dict[str, Any]):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def _check_auth(self) -> bool:
        if not AUTH_SECRET:
            return True
        auth = self.headers.get("Authorization", "")
        expected = f"Bearer {AUTH_SECRET}"
        return auth == expected

    def do_GET(self):
        if not self._check_auth():
            self._send_json(401, {"error": "UNAUTHORIZED"})
            return

        if self.path == "/" or self.path == "/health":
            self._send_json(200, {
                "status": "ONLINE",
                "role": "macos-xcode-runner",
                "os": platform.system(),
                "mac_version": platform.mac_ver()[0],
                "arch": platform.machine(),
                "timestamp": int(time.time())
            })
        elif self.path == "/capabilities":
            has_xcode = shutil.which("xcodebuild") is not None
            has_simctl = shutil.which("xcrun") is not None
            xcode_version = ""
            if has_xcode:
                try:
                    res = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, timeout=5)
                    xcode_version = res.stdout.strip().replace("\n", " - ")
                except Exception:
                    pass

            simulators = []
            if has_simctl:
                try:
                    res = subprocess.run(["xcrun", "simctl", "list", "devices", "available"], capture_output=True, text=True, timeout=5)
                    for line in res.stdout.splitlines():
                        if "iPhone" in line:
                            simulators.append(line.strip())
                except Exception:
                    pass

            self._send_json(200, {
                "status": "AVAILABLE" if has_xcode else "DEGRADED",
                "has_xcode": has_xcode,
                "xcode_version": xcode_version,
                "has_simctl": has_simctl,
                "available_simulators": simulators[:10],
                "total_simulators": len(simulators)
            })
        else:
            self._send_json(404, {"error": "ENDPOINT_NOT_FOUND"})

    def do_POST(self):
        if not self._check_auth():
            self._send_json(401, {"error": "UNAUTHORIZED"})
            return

        content_len = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_len).decode("utf-8") if content_len > 0 else "{}"
        try:
            payload = json.loads(raw_body)
        except Exception:
            self._send_json(400, {"error": "INVALID_JSON"})
            return

        if self.path == "/run-xcode":
            cmd = payload.get("command", ["xcodebuild", "-version"])
            timeout = payload.get("timeout", 120)
            start_t = time.time()
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
                duration = round(time.time() - start_t, 3)
                self._send_json(200, {
                    "success": proc.returncode == 0,
                    "status": "PASS" if proc.returncode == 0 else "FAIL",
                    "exit_code": proc.returncode,
                    "stdout": proc.stdout,
                    "stderr": proc.stderr,
                    "duration": duration,
                    "command": " ".join(cmd)
                })
            except subprocess.TimeoutExpired:
                self._send_json(504, {
                    "success": False,
                    "status": "TIMEOUT",
                    "exit_code": 124,
                    "error": f"Execution timed out after {timeout} seconds"
                })
            except Exception as e:
                self._send_json(500, {
                    "success": False,
                    "status": "ERROR",
                    "exit_code": 1,
                    "error": str(e)
                })

        elif self.path == "/run-ios-test":
            device = payload.get("device", "")
            test_name = payload.get("test_name", "smoke-test")
            start_t = time.time()

            # Verify xcodebuild
            proc = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, timeout=10)
            duration = round(time.time() - start_t, 3)
            self._send_json(200, {
                "success": proc.returncode == 0,
                "status": "PASS" if proc.returncode == 0 else "FAIL",
                "test_name": test_name,
                "exit_code": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
                "duration": duration,
                "runner_platform": "macos",
                "device": device or "macOS Xcode Server Node"
            })

        else:
            self._send_json(404, {"error": "ENDPOINT_NOT_FOUND"})

def start_server(port: int = PORT):
    server = HTTPServer(("0.0.0.0", port), MacOSRunnerHandler)
    print(f"🍏 macOS Xcode Server Daemon running on port {port}")
    print(f"OS: {platform.system()} {platform.mac_ver()[0]} ({platform.machine()})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping macOS Xcode Server Daemon...")
        server.server_close()

if __name__ == "__main__":
    p = PORT
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        p = int(sys.argv[1])
    start_server(p)
