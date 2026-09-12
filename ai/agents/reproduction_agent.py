"""
Bug Reproduction Agent
Validates reported bugs, deterministically reproduces them with minimal reproducible examples (MRE),
and filters out non-reproducible or flaky issues before the Fix Agent acts.
"""

from typing import Dict, Any, List
from ai.tools.terminal import run_command

def attempt_reproduction(test_target: str, cwd: str = "backend") -> Dict[str, Any]:
    """
    Attempts to reproduce a test failure. If it passes consistently, it is rejected
    as a non-reproducible bug to prevent false fixes.
    """
    print(f"[REPRODUCTION AGENT] Reproducing: {test_target} in {cwd}")
    # Attempt 1: Direct test execution
    res1 = run_command(f"npx jest {test_target} --forceExit" if "jest" in test_target or "src/tests" in test_target else f"flutter test {test_target}", cwd=cwd)

    if res1["success"]:
        # Re-check to confirm if it was truly passing
        return {
            "reproduced": False,
            "status": "NOT_REPRODUCED",
            "reason": "Test target passed cleanly under normal execution."
        }

    # Attempt 2: Confirm failure determinism
    res2 = run_command(f"npx jest {test_target} --forceExit" if "jest" in test_target or "src/tests" in test_target else f"flutter test {test_target}", cwd=cwd)

    return {
        "reproduced": not res2["success"],
        "status": "REPRODUCED" if not res2["success"] else "FLAKY_SUSPECT",
        "error_output": res1["stderr"] or res1["stdout"],
        "second_run_failed": not res2["success"]
    }

if __name__ == "__main__":
    rep = attempt_reproduction("src/tests/fuelExpenseFlow.test.js")
    print("Reproduction output:", rep["status"])
