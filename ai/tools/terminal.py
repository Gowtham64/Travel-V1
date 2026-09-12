"""
Terminal Execution Tool
Provides safe command execution with timeouts, process isolation, and output capture.
"""

import subprocess
import os
import time
from typing import Dict, Any, Optional

def run_command(command: str, cwd: Optional[str] = None, timeout: int = 120, env: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """
    Executes a shell command safely, capturing stdout, stderr, execution duration, and exit code.
    """
    start_time = time.time()
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)

    try:
        proc = subprocess.Popen(
            command,
            shell=True,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=merged_env
        )
        stdout, stderr = proc.communicate(timeout=timeout)
        duration = round(time.time() - start_time, 2)
        return {
            "command": command,
            "exit_code": proc.returncode,
            "stdout": stdout.strip(),
            "stderr": stderr.strip(),
            "duration_seconds": duration,
            "success": proc.returncode == 0,
            "timed_out": False
        }
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        duration = round(time.time() - start_time, 2)
        return {
            "command": command,
            "exit_code": -1,
            "stdout": stdout.strip() if stdout else "",
            "stderr": f"Command timed out after {timeout} seconds. {stderr.strip() if stderr else ''}",
            "duration_seconds": duration,
            "success": False,
            "timed_out": True
        }
    except Exception as e:
        return {
            "command": command,
            "exit_code": -1,
            "stdout": "",
            "stderr": str(e),
            "duration_seconds": round(time.time() - start_time, 2),
            "success": False,
            "timed_out": False
        }

if __name__ == "__main__":
    res = run_command("echo 'Terminal tool operational'")
    print(res)
