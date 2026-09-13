"""
Base Execution Runner Interface.
Enforces real execution: command, working directory, timeout, audit logging, exit code, stdout, stderr, and duration.
ABSOLUTE NO-MOCK RULE: Every result must come from actual system execution.
"""

import os
import sys
import time
import subprocess
from typing import Dict, Any, List, Optional

class BaseRunner:
    def __init__(self, runner_id: str, name: str, platform: str):
        self.runner_id = runner_id
        self.name = name
        self.platform = platform

    def execute_command(self, cmd: List[str], cwd: str = None, timeout_sec: int = 120, env: Dict[str, str] = None) -> Dict[str, Any]:
        """Executes a real shell command and returns verified results."""
        start_time = time.time()
        exec_env = os.environ.copy()
        if env:
            exec_env.update(env)

        try:
            process = subprocess.run(
                cmd,
                cwd=cwd or os.getcwd(),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout_sec,
                env=exec_env
            )
            duration = round(time.time() - start_time, 3)
            return {
                "success": process.returncode == 0,
                "exit_code": process.returncode,
                "stdout": process.stdout,
                "stderr": process.stderr,
                "duration": duration,
                "command": " ".join(cmd),
                "cwd": cwd or os.getcwd()
            }
        except subprocess.TimeoutExpired as e:
            duration = round(time.time() - start_time, 3)
            return {
                "success": False,
                "exit_code": 124,
                "stdout": e.stdout or "",
                "stderr": f"Command timed out after {timeout_sec} seconds.",
                "duration": duration,
                "command": " ".join(cmd),
                "cwd": cwd or os.getcwd()
            }
        except Exception as e:
            duration = round(time.time() - start_time, 3)
            return {
                "success": False,
                "exit_code": 1,
                "stdout": "",
                "stderr": str(e),
                "duration": duration,
                "command": " ".join(cmd),
                "cwd": cwd or os.getcwd()
            }
