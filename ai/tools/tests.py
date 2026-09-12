"""
Test Runner Tool
Orchestrates test execution across backend (Jest), mobile (Flutter), and web (Playwright).
Parses outputs into structured failure summaries for the Debug Agent.
"""

import re
from typing import Dict, Any, List, Optional
from ai.tools.terminal import run_command

def run_backend_tests(test_path: Optional[str] = None, cwd: str = "backend", timeout: int = 120) -> Dict[str, Any]:
    """Runs backend Jest tests and extracts failures and pass counts."""
    cmd = f"npx jest {test_path} --forceExit" if test_path else "npm test -- --forceExit"
    res = run_command(cmd, cwd=cwd, timeout=timeout)

    output = f"{res['stdout']}\n{res['stderr']}"
    failed_tests = []
    
    # Parse Jest test failures
    fail_matches = re.findall(r"FAIL\s+(src/tests/[^\s]+)", output)
    for m in fail_matches:
        failed_tests.append(m)

    summary_match = re.search(r"Tests:\s+(.*)", output)
    summary = summary_match.group(1) if summary_match else ("Passed" if res["success"] else "Failed")

    return {
        "suite": "backend",
        "command": cmd,
        "success": res["success"],
        "failed_files": list(set(failed_tests)),
        "summary": summary,
        "raw_output": output[-4000:] if len(output) > 4000 else output,
        "duration_seconds": res["duration_seconds"]
    }

def run_mobile_tests(test_path: Optional[str] = None, cwd: str = "mobile", timeout: int = 120) -> Dict[str, Any]:
    """Runs Flutter unit & widget tests and extracts failure details."""
    cmd = f"flutter test {test_path}" if test_path else "flutter test"
    res = run_command(cmd, cwd=cwd, timeout=timeout)

    output = f"{res['stdout']}\n{res['stderr']}"
    failed = []
    
    # Match Flutter test failures
    for line in output.splitlines():
        if "FAIL" in line or "[E]" in line or "Some tests failed" in line:
            failed.append(line.strip())

    summary_match = re.search(r"(\d+\s+tests?\s+passed[^\n]*)", output, re.IGNORECASE)
    summary = summary_match.group(1) if summary_match else ("All tests passed" if res["success"] else "Tests failed")

    return {
        "suite": "mobile",
        "command": cmd,
        "success": res["success"],
        "failed_tests": failed[:10],
        "summary": summary,
        "raw_output": output[-4000:] if len(output) > 4000 else output,
        "duration_seconds": res["duration_seconds"]
    }

def run_all_verification(cwd_root: str = ".") -> Dict[str, Any]:
    """Runs all primary test suites to verify project integrity."""
    backend_res = run_backend_tests(cwd=f"{cwd_root}/backend" if cwd_root != "." else "backend")
    mobile_res = run_mobile_tests(cwd=f"{cwd_root}/mobile" if cwd_root != "." else "mobile")

    overall_success = backend_res["success"] and mobile_res["success"]
    return {
        "all_passed": overall_success,
        "backend": backend_res,
        "mobile": mobile_res,
        "failures": (backend_res["failed_files"] if not backend_res["success"] else []) +
                    (mobile_res["failed_tests"] if not mobile_res["success"] else [])
    }

if __name__ == "__main__":
    print("Running quick test runner check...")
    res = run_backend_tests("src/tests/budgetService.test.js")
    print("Backend test check result:", res["success"], res["summary"])
