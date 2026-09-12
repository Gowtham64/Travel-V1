"""
Debug & Root Cause Agent
Analyzes failure logs, stack traces, and relevant source code to locate the root cause
and formulate a targeted minimal repair plan.
"""

import re
from typing import Dict, Any, List
from ai.tools.filesystem import read_file, search_code

def diagnose_failure(error_log: str, component: str = "backend") -> Dict[str, Any]:
    """Extracts affected files, line numbers, and error patterns from failure logs."""
    affected_files = []
    
    # Extract file paths from stack trace patterns
    path_patterns = [
        r"(?:at\s+.*?\((.*?):(\d+):(\d+)\))",
        r"(?:(src/[^\s:]+):(\d+):(\d+))",
        r"(?:(lib/[^\s:]+):(\d+):(\d+))"
    ]

    for pat in path_patterns:
        matches = re.findall(pat, error_log)
        for m in matches:
            filepath = m[0]
            line_no = m[1]
            if not any(filepath.endswith(ign) for ign in [".test.js", "_test.dart", "node_modules"]):
                affected_files.append({"file": filepath, "line": int(line_no)})

    # Deduplicate files
    unique_files = []
    seen = set()
    for f in affected_files:
        if f["file"] not in seen:
            seen.add(f["file"])
            unique_files.append(f)

    # Basic root cause heuristics
    root_cause_summary = "Logic or assertion mismatch detected in test execution."
    if "TypeError" in error_log:
        root_cause_summary = "Null or undefined variable reference in pipeline."
    elif "assertion" in error_log.lower():
        root_cause_summary = "Failed mathematical assertion or response contract violation."
    elif "timeout" in error_log.lower():
        root_cause_summary = "Network call or asynchronous operation timed out."

    return {
        "component": component,
        "affected_files": unique_files[:5],
        "root_cause_summary": root_cause_summary,
        "recommended_action": "Inspect affected functions, ensure defensive null checks, and verify contract bounds."
    }

if __name__ == "__main__":
    sample = "FAIL src/tests/trip.route.test.js\n at src/services/budgetService.js:102:15"
    d = diagnose_failure(sample)
    print("Diagnosis:", d)
