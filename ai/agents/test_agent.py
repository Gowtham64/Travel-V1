"""
Test Agent
Executes test suites across backend, mobile, and web, and generates combination tests
based on tests/matrix.yaml.
"""

from typing import Dict, Any, List
from ai.tools.tests import run_backend_tests, run_mobile_tests, run_all_verification
from ai.tools.terminal import run_command

def execute_smoke_and_regression(root_dir: str = ".") -> Dict[str, Any]:
    """Runs the primary test suites and collates any failure reports."""
    print("[TEST AGENT] Executing full verification suites...")
    res = run_all_verification(cwd_root=root_dir)
    return res

def run_flaky_check(test_command: str, cwd: str = ".", repeat: int = 5) -> Dict[str, Any]:
    """Runs a test repeatedly to classify if failures are deterministic or flaky."""
    passes = 0
    failures = 0
    outputs = []

    print(f"[TEST AGENT] Running flaky detection on: {test_command} ({repeat} runs)")
    for i in range(repeat):
        res = run_command(test_command, cwd=cwd)
        if res["success"]:
            passes += 1
        else:
            failures += 1
            outputs.append(res["stderr"] or res["stdout"])

    is_flaky = (passes > 0 and failures > 0)
    is_genuine_failure = (passes == 0 and failures > 0)

    return {
        "command": test_command,
        "runs": repeat,
        "passes": passes,
        "failures": failures,
        "is_flaky": is_flaky,
        "is_genuine_failure": is_genuine_failure,
        "sample_failure": outputs[0] if outputs else None
    }

if __name__ == "__main__":
    v = execute_smoke_and_regression()
    print("Verification result:", v["all_passed"])
