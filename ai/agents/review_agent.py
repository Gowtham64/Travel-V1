"""
Review Agent
Audits proposed code changes against architectural invariants, conventions,
and minimal blast radius rules before PR generation.
"""

from typing import Dict, Any, List
from ai.tools.git import get_diff, get_status
from ai.agents.security_agent import scan_security_and_integrity

def review_patch(bug_title: str) -> Dict[str, Any]:
    """Inspects the uncommitted patch and gives an approval verdict."""
    st = get_status()
    diff = get_diff()
    sec = scan_security_and_integrity()

    reasons = []
    if not sec["passed"]:
        reasons.extend(sec["issues"])

    if len(st["modified"]) > 10:
        reasons.append(f"Diff touched {len(st['modified'])} files, exceeding minimal change threshold (>10 files).")

    if not diff.strip():
        reasons.append("Empty diff detected; no changes to review.")

    approved = len(reasons) == 0
    return {
        "approved": approved,
        "bug_title": bug_title,
        "modified_files": st["modified"],
        "diff_lines": len(diff.splitlines()),
        "rejection_reasons": reasons if not approved else []
    }

if __name__ == "__main__":
    r = review_patch("Test bug")
    print("Review verdict:", r["approved"])
