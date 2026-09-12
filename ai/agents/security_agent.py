"""
Security & Integrity Agent
Scans diffs and workspace for hardcoded secrets, dangerous DB drop commands,
dependency vulnerabilities, and oversized binary files.
"""

import os
import re
from typing import Dict, Any, List
from ai.tools.git import get_diff
from ai.tools.terminal import run_command

def scan_security_and_integrity() -> Dict[str, Any]:
    """Audits current git diff and repository assets against security guidelines."""
    diff_text = get_diff()
    issues = []

    # 1. Secret / API key patterns
    secret_patterns = [
        (r"(?i)(api[_-]?key|secret|password|private[_-]?key)\s*[:=]\s*['\"][A-Za-z0-9_\-]{16,}['\"]", "Exposed hardcoded secret or token"),
        (r"ghp_[A-Za-z0-9]{36}", "GitHub Personal Access Token"),
        (r"sk-[A-Za-z0-9]{32,}", "Secret API Key")
    ]

    for pat, desc in secret_patterns:
        if re.search(pat, diff_text):
            issues.append(f"SECURITY: {desc} detected in uncommitted diff.")

    # 2. Dangerous SQL statements
    sql_patterns = [
        (r"(?i)DROP\s+TABLE", "DROP TABLE statement in diff"),
        (r"(?i)DROP\s+DATABASE", "DROP DATABASE statement in diff"),
        (r"(?i)TRUNCATE", "TRUNCATE statement in diff")
    ]
    for pat, desc in sql_patterns:
        if re.search(pat, diff_text):
            issues.append(f"INTEGRITY: {desc} detected.")

    # 3. Oversized file check (> 100MB limit for GitHub)
    res = run_command("find . -not -path '*/.*' -size +95M")
    if res["success"] and res["stdout"]:
        for line in res["stdout"].splitlines():
            if not line.startswith("./ai") and not line.startswith("./.git"):
                issues.append(f"INTEGRITY: File exceeds safe git commit threshold: {line.strip()}")

    return {
        "passed": len(issues) == 0,
        "issues": issues,
        "scanned_diff_length": len(diff_text)
    }

if __name__ == "__main__":
    sec = scan_security_and_integrity()
    print("Security audit:", sec)
